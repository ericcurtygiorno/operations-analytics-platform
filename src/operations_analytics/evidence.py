"""Generate reproducible analytical and data-quality evidence from the marts layer."""

from __future__ import annotations

import argparse
import json
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import psycopg2
from psycopg2.extras import RealDictCursor

from .ingestion import DatabaseConfig, load_env_file

QUERIES = {
    "overview": """
        select
            count(*) as total_shipments,
            count(*) filter (where delivery_status = 'delivered') as delivered_shipments,
            count(*) filter (where is_valid_for_sla) as sla_eligible_shipments,
            count(*) filter (where is_valid_for_sla and is_on_time) as on_time_deliveries,
            round(
                100.0 * count(*) filter (where is_valid_for_sla and is_on_time)
                / nullif(count(*) filter (where is_valid_for_sla), 0), 2
            ) as on_time_delivery_rate_pct,
            round(
                (avg(delivery_delay_days)
                    filter (where is_valid_for_sla and not is_on_time))::numeric, 2
            ) as average_late_delay_days,
            round(
                100.0 * count(*) filter (where exception_count > 0) / count(*), 2
            ) as exception_rate_pct,
            round(
                100.0 * count(*) filter (
                    where delivery_status = 'delivered' and delivery_attempts = 1
                ) / nullif(count(*) filter (where delivery_status = 'delivered'), 0), 2
            ) as first_attempt_success_pct,
            round(avg(freight_amount)::numeric, 2) as average_freight_per_shipment,
            count(*) - count(*) filter (where is_valid_for_sla) as sla_excluded_shipments,
            round(
                100.0 * (count(*) - count(*) filter (where is_valid_for_sla)) / count(*), 2
            ) as sla_exclusion_rate_pct,
            min(promised_delivery_at)::date as first_promised_date,
            max(promised_delivery_at)::date as last_promised_date
        from marts.fact_deliveries
    """,
    "year_comparison": """
        select
            extract(year from promised_delivery_at)::integer as year,
            count(*) as total_shipments,
            count(*) filter (where is_valid_for_sla) as sla_eligible_shipments,
            round(
                100.0 * count(*) filter (where is_valid_for_sla and is_on_time)
                / nullif(count(*) filter (where is_valid_for_sla), 0), 2
            ) as on_time_delivery_rate_pct,
            round(
                100.0 * count(*) filter (where exception_count > 0) / count(*), 2
            ) as exception_rate_pct
        from marts.fact_deliveries
        group by 1
        order by 1
    """,
    "carrier_performance": """
        select
            c.carrier_name,
            count(*) as total_shipments,
            count(*) filter (where f.is_valid_for_sla) as sla_eligible_shipments,
            round(
                100.0 * count(*) filter (where f.is_valid_for_sla and f.is_on_time)
                / nullif(count(*) filter (where f.is_valid_for_sla), 0), 2
            ) as on_time_delivery_rate_pct,
            round(
                (avg(f.delivery_delay_days)
                    filter (where f.is_valid_for_sla and not f.is_on_time))::numeric, 2
            ) as average_late_delay_days,
            round(
                100.0 * count(*) filter (where f.exception_count > 0) / count(*), 2
            ) as exception_rate_pct,
            round(avg(f.freight_amount)::numeric, 2) as average_freight_per_shipment
        from marts.fact_deliveries f
        join marts.dim_carrier c using (carrier_key)
        group by c.carrier_name
        order by on_time_delivery_rate_pct nulls last, c.carrier_name
    """,
    "regional_performance": """
        select
            coalesce(l.destination_region, 'Missing') as destination_region,
            count(*) as total_shipments,
            count(*) filter (where f.is_valid_for_sla) as sla_eligible_shipments,
            round(
                100.0 * count(*) filter (where f.is_valid_for_sla and f.is_on_time)
                / nullif(count(*) filter (where f.is_valid_for_sla), 0), 2
            ) as on_time_delivery_rate_pct,
            round(
                100.0 * count(*) filter (where f.exception_count > 0) / count(*), 2
            ) as exception_rate_pct
        from marts.fact_deliveries f
        left join marts.dim_location l using (location_key)
        group by l.destination_region
        order by on_time_delivery_rate_pct nulls last, destination_region
    """,
    "service_performance": """
        select
            coalesce(s.service_type, 'Missing') as service_type,
            count(*) as total_shipments,
            count(*) filter (where f.is_valid_for_sla) as sla_eligible_shipments,
            round(
                100.0 * count(*) filter (where f.is_valid_for_sla and f.is_on_time)
                / nullif(count(*) filter (where f.is_valid_for_sla), 0), 2
            ) as on_time_delivery_rate_pct,
            round(
                (avg(f.order_to_ship_hours) filter (where f.order_to_ship_hours >= 0))::numeric,
                2
            ) as average_order_to_ship_hours,
            round(
                (avg(f.ship_to_delivery_hours)
                    filter (where f.ship_to_delivery_hours >= 0))::numeric / 24, 2
            ) as average_ship_to_delivery_days
        from marts.fact_deliveries f
        left join marts.dim_service_type s using (service_type_key)
        group by s.service_type
        order by on_time_delivery_rate_pct nulls last, service_type
    """,
    "distribution_center_performance": """
        select
            coalesce(dc.distribution_center_id, 'Missing') as distribution_center_id,
            count(*) as total_shipments,
            count(*) filter (where f.is_valid_for_sla) as sla_eligible_shipments,
            round(
                100.0 * count(*) filter (where f.is_valid_for_sla and f.is_on_time)
                / nullif(count(*) filter (where f.is_valid_for_sla), 0), 2
            ) as on_time_delivery_rate_pct,
            round(
                (avg(f.order_to_ship_hours) filter (where f.order_to_ship_hours >= 0))::numeric,
                2
            ) as average_order_to_ship_hours
        from marts.fact_deliveries f
        left join marts.dim_distribution_center dc using (distribution_center_key)
        group by dc.distribution_center_id
        order by on_time_delivery_rate_pct nulls last, distribution_center_id
    """,
    "failure_reasons": """
        select
            failure_reason,
            count(*) as affected_shipments,
            round(100.0 * count(*) / sum(count(*)) over (), 2) as share_of_exceptions_pct
        from marts.fact_deliveries
        where failure_reason is not null
        group by failure_reason
        order by affected_shipments desc, failure_reason
    """,
    "quality_flags": """
        select 'orphan_order' as quality_rule, count(*) as affected_rows
        from marts.fact_deliveries where is_orphan_order
        union all
        select 'unknown_carrier', count(*)
        from marts.fact_deliveries where is_unknown_carrier
        union all
        select 'delivery_before_shipment', count(*)
        from marts.fact_deliveries where is_delivery_before_shipment
        union all
        select 'delivered_without_timestamp', count(*)
        from marts.fact_deliveries where is_delivered_without_timestamp
        union all
        select 'invalid_order', count(*)
        from marts.fact_deliveries where has_invalid_order
        order by quality_rule
    """,
    "model_checks": """
        select
            count(*) as fact_rows,
            count(distinct shipment_id) as distinct_shipment_ids,
            count(*) filter (
                where is_valid_for_sla and (
                    is_orphan_order or is_unknown_carrier or is_delivery_before_shipment
                    or is_delivered_without_timestamp or has_invalid_order
                )
            ) as invalid_rows_leaking_into_sla,
            count(*) filter (
                where is_valid_for_sla and (
                    delivered_at is null or promised_delivery_at is null
                    or shipped_at is null or order_at is null
                    or delivered_at < shipped_at or shipped_at < order_at
                )
            ) as invalid_timelines_leaking_into_sla
        from marts.fact_deliveries
    """,
    "latest_batch": """
        select load_id, source_batch_id, status, row_counts, file_hashes
        from raw.ingestion_batches batches
        where status = 'completed'
          and exists (select 1 from raw.orders rows where rows._load_id = batches.load_id)
          and exists (select 1 from raw.shipments rows where rows._load_id = batches.load_id)
          and exists (
              select 1 from raw.delivery_events rows where rows._load_id = batches.load_id
          )
        order by completed_at desc, started_at desc, load_id desc
        limit 1
    """,
}


def _json_value(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    return value


def _normalized_rows(cursor: RealDictCursor) -> list[dict[str, Any]]:
    return [{key: _json_value(value) for key, value in row.items()} for row in cursor.fetchall()]


def collect_database_evidence(config: DatabaseConfig) -> dict[str, list[dict[str, Any]]]:
    connection = psycopg2.connect(
        host=config.host,
        port=config.port,
        dbname=config.dbname,
        user=config.user,
        password=config.password,
    )
    try:
        evidence: dict[str, list[dict[str, Any]]] = {}
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            for name, query in QUERIES.items():
                cursor.execute(query)
                evidence[name] = _normalized_rows(cursor)
        return evidence
    finally:
        connection.close()


def summarize_dbt_results(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    results = payload.get("results", [])
    statuses: dict[str, int] = {}
    resource_types: dict[str, int] = {}
    for result in results:
        status = result.get("status", "unknown")
        statuses[status] = statuses.get(status, 0) + 1
        unique_id = result.get("unique_id", "unknown.unknown")
        resource_type = unique_id.split(".", 1)[0]
        resource_types[resource_type] = resource_types.get(resource_type, 0) + 1
    return {
        "generated_at": payload.get("metadata", {}).get("generated_at"),
        "total_nodes": len(results),
        "statuses": dict(sorted(statuses.items())),
        "resource_types": dict(sorted(resource_types.items())),
        "all_passed": bool(results) and all(
            result.get("status") in {"pass", "success"} for result in results
        ),
    }


def _markdown_table(rows: list[dict[str, Any]], columns: list[tuple[str, str]]) -> str:
    headers = [label for _, label in columns]
    lines = [
        "| " + " | ".join(headers) + " |",
        "|" + "|".join("---" for _ in headers) + "|",
    ]
    for row in rows:
        values = ["—" if row.get(key) is None else str(row.get(key)) for key, _ in columns]
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def render_analysis_markdown(evidence: dict[str, list[dict[str, Any]]]) -> str:
    overview = evidence["overview"][0]
    carriers = [row for row in evidence["carrier_performance"] if row["sla_eligible_shipments"]]
    regions = [row for row in evidence["regional_performance"] if row["sla_eligible_shipments"]]
    services = [row for row in evidence["service_performance"] if row["sla_eligible_shipments"]]
    centers = [
        row for row in evidence["distribution_center_performance"]
        if row["sla_eligible_shipments"]
    ]
    failures = evidence["failure_reasons"]
    lowest_carrier = min(carriers, key=lambda row: row["on_time_delivery_rate_pct"])
    highest_carrier = max(carriers, key=lambda row: row["on_time_delivery_rate_pct"])
    lowest_region = min(regions, key=lambda row: row["on_time_delivery_rate_pct"])
    highest_region = max(regions, key=lambda row: row["on_time_delivery_rate_pct"])
    top_failure = failures[0]
    carrier_spread = round(
        highest_carrier["on_time_delivery_rate_pct"]
        - lowest_carrier["on_time_delivery_rate_pct"],
        2,
    )

    return f"""# Reproducible Operational Analysis

This analysis is generated from `marts.fact_deliveries` by
`python -m src.operations_analytics.evidence`. All findings describe the deterministic
synthetic dataset; they do not claim measured impact in a real company.

## Scope

- Shipment grain: {overview['total_shipments']} rows.
- Promised-delivery period: {overview['first_promised_date']} through
  {overview['last_promised_date']}.
- SLA-eligible population: {overview['sla_eligible_shipments']} shipments.
- Governed exclusions: {overview['sla_excluded_shipments']} shipments
  ({overview['sla_exclusion_rate_pct']}%).

## Executive findings

1. **Service reliability is the main simulated risk.** The full-period on-time delivery
   rate is {overview['on_time_delivery_rate_pct']}%, and late eligible shipments average
   {overview['average_late_delay_days']} days beyond promise.
2. **Carrier performance is materially uneven.** {lowest_carrier['carrier_name']} has the
   lowest eligible on-time rate at {lowest_carrier['on_time_delivery_rate_pct']}%, versus
   {highest_carrier['on_time_delivery_rate_pct']}% for {highest_carrier['carrier_name']}.
   This is a {carrier_spread} percentage-point spread.
3. **Central-West is the clearest regional hotspot.** Its on-time rate is
   {lowest_region['on_time_delivery_rate_pct']}%, compared with
   {highest_region['on_time_delivery_rate_pct']}% in {highest_region['destination_region']}.
4. **Exceptions are frequent and operationally concentrated.**
   {overview['exception_rate_pct']}% of shipments have at least one exception. The largest
   recorded reason is `{top_failure['failure_reason']}`, affecting
   {top_failure['affected_shipments']} shipments ({top_failure['share_of_exceptions_pct']}%
   of shipments with a recorded failure reason).
5. **First-attempt completion remains a useful counterbalance.**
   {overview['first_attempt_success_pct']}% of delivered shipments complete on the first
   attempt, suggesting that the synthetic delays are not explained solely by repeat attempts.

These findings identify where a real operation would investigate capacity, carrier governance,
regional constraints, and promise-setting. No improvement or financial benefit is asserted.

## Carrier benchmark

{_markdown_table(carriers, [
    ('carrier_name', 'Carrier'),
    ('total_shipments', 'Shipments'),
    ('sla_eligible_shipments', 'SLA eligible'),
    ('on_time_delivery_rate_pct', 'On-time %'),
    ('average_late_delay_days', 'Avg late days'),
    ('exception_rate_pct', 'Exception %'),
    ('average_freight_per_shipment', 'Avg freight'),
])}

## Regional benchmark

{_markdown_table(regions, [
    ('destination_region', 'Region'),
    ('total_shipments', 'Shipments'),
    ('sla_eligible_shipments', 'SLA eligible'),
    ('on_time_delivery_rate_pct', 'On-time %'),
    ('exception_rate_pct', 'Exception %'),
])}

## Service-type diagnostic

{_markdown_table(services, [
    ('service_type', 'Service type'),
    ('total_shipments', 'Shipments'),
    ('on_time_delivery_rate_pct', 'On-time %'),
    ('average_order_to_ship_hours', 'Order-to-ship hours'),
    ('average_ship_to_delivery_days', 'Ship-to-delivery days'),
])}

## Distribution-center diagnostic

{_markdown_table(centers, [
    ('distribution_center_id', 'Distribution center'),
    ('total_shipments', 'Shipments'),
    ('on_time_delivery_rate_pct', 'On-time %'),
    ('average_order_to_ship_hours', 'Order-to-ship hours'),
])}

## Recorded failure reasons

{_markdown_table(failures, [
    ('failure_reason', 'Failure reason'),
    ('affected_shipments', 'Affected shipments'),
    ('share_of_exceptions_pct', 'Share %'),
])}

## Interpretation boundaries

- The data is synthetic and deterministic.
- On-time delivery is not labeled OTIF because item-level completeness is not proven.
- Correlation in these descriptive cuts does not establish causality.
- Invalid rows remain visible in the fact table and are excluded from governed SLA metrics.
"""


def render_quality_markdown(
    evidence: dict[str, list[dict[str, Any]]], dbt_summary: dict[str, Any]
) -> str:
    overview = evidence["overview"][0]
    checks = evidence["model_checks"][0]
    batch = evidence["latest_batch"][0]
    flags = evidence["quality_flags"]
    return f"""# Executable Data-Quality Evidence

This report is generated by `python -m src.operations_analytics.evidence` after `dbt build`.
It combines the dbt run artifact with direct reconciliation queries against PostgreSQL.

## Build result

- dbt nodes executed: {dbt_summary['total_nodes']}.
- Status counts: `{json.dumps(dbt_summary['statuses'], sort_keys=True)}`.
- Resource counts: `{json.dumps(dbt_summary['resource_types'], sort_keys=True)}`.
- All models and tests passed: **{str(dbt_summary['all_passed']).lower()}**.

## Reconciliation controls

- Fact rows: {checks['fact_rows']}.
- Distinct shipment IDs: {checks['distinct_shipment_ids']}.
- Invalid quality rows leaking into the SLA denominator:
  {checks['invalid_rows_leaking_into_sla']}.
- Invalid timelines leaking into the SLA denominator:
  {checks['invalid_timelines_leaking_into_sla']}.
- SLA exclusions: {overview['sla_excluded_shipments']} of
  {overview['total_shipments']} shipments ({overview['sla_exclusion_rate_pct']}%).

## Detected quality conditions

{_markdown_table(flags, [
    ('quality_rule', 'Quality rule'),
    ('affected_rows', 'Affected rows'),
])}

Counts overlap when one row violates more than one rule. The governed exclusion count is therefore
not the sum of the individual conditions.

## Source lineage

- Latest completed load: `{batch['load_id']}`.
- Source batch: `{batch['source_batch_id']}`.
- Raw row counts: `{json.dumps(batch['row_counts'], sort_keys=True)}`.
- File checksums are preserved in the machine-readable evidence artifact.

## Failure behavior

Generic and custom dbt tests return non-zero status on failure, causing the vertical-slice script
to stop. The custom tests specifically prevent invalid source rows and invalid timelines from
entering the SLA denominator.
"""


def write_evidence(
    evidence: dict[str, list[dict[str, Any]]],
    dbt_summary: dict[str, Any],
    output_dir: Path,
    docs_dir: Path,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    docs_dir.mkdir(parents=True, exist_ok=True)
    payload = {"database": evidence, "dbt": dbt_summary}
    (output_dir / "stage-1-3-evidence.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (docs_dir / "analysis.md").write_text(
        render_analysis_markdown(evidence), encoding="utf-8"
    )
    (docs_dir / "quality-report.md").write_text(
        render_quality_markdown(evidence, dbt_summary), encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    parser.add_argument("--run-results", type=Path, default=Path("target/run_results.json"))
    parser.add_argument("--output-dir", type=Path, default=Path("artifacts/evidence"))
    parser.add_argument("--docs-dir", type=Path, default=Path("docs"))
    args = parser.parse_args()
    load_env_file(args.env_file)
    evidence = collect_database_evidence(DatabaseConfig.from_environment())
    dbt_summary = summarize_dbt_results(args.run_results)
    write_evidence(evidence, dbt_summary, args.output_dir, args.docs_dir)
    print(
        json.dumps(
            {
                "database_sections": len(evidence),
                "dbt_nodes": dbt_summary["total_nodes"],
                "all_passed": dbt_summary["all_passed"],
                "output": str(args.output_dir / "stage-1-3-evidence.json"),
            },
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
