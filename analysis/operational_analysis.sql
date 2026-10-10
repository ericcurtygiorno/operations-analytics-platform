-- Reproducible analytical query pack for the Operations Analytics Platform.
-- Run after dbt build against PostgreSQL database operations_analytics.

-- Executive KPI reconciliation.
select
    count(*) as total_shipments,
    count(*) filter (where is_valid_for_sla) as sla_eligible_shipments,
    round(
        100.0 * count(*) filter (where is_valid_for_sla and is_on_time)
        / nullif(count(*) filter (where is_valid_for_sla), 0),
        2
    ) as on_time_delivery_rate_pct,
    round(
        (avg(delivery_delay_days)
            filter (where is_valid_for_sla and not is_on_time))::numeric,
        2
    ) as average_late_delay_days,
    round(100.0 * count(*) filter (where exception_count > 0) / count(*), 2)
        as exception_rate_pct,
    round(avg(freight_amount)::numeric, 2) as average_freight_per_shipment
from marts.fact_deliveries;

-- Carrier benchmark with scale and service context.
select
    c.carrier_name,
    count(*) as total_shipments,
    count(*) filter (where f.is_valid_for_sla) as sla_eligible_shipments,
    round(
        100.0 * count(*) filter (where f.is_valid_for_sla and f.is_on_time)
        / nullif(count(*) filter (where f.is_valid_for_sla), 0),
        2
    ) as on_time_delivery_rate_pct,
    round(100.0 * count(*) filter (where f.exception_count > 0) / count(*), 2)
        as exception_rate_pct,
    round(avg(f.freight_amount)::numeric, 2) as average_freight_per_shipment
from marts.fact_deliveries f
join marts.dim_carrier c using (carrier_key)
group by c.carrier_name
order by on_time_delivery_rate_pct nulls last;

-- Regional hotspot analysis.
select
    coalesce(l.destination_region, 'Missing') as destination_region,
    count(*) as total_shipments,
    round(
        100.0 * count(*) filter (where f.is_valid_for_sla and f.is_on_time)
        / nullif(count(*) filter (where f.is_valid_for_sla), 0),
        2
    ) as on_time_delivery_rate_pct,
    round(100.0 * count(*) filter (where f.exception_count > 0) / count(*), 2)
        as exception_rate_pct
from marts.fact_deliveries f
left join marts.dim_location l using (location_key)
group by l.destination_region
order by on_time_delivery_rate_pct nulls last;

-- Failure-reason Pareto input.
select
    failure_reason,
    count(*) as affected_shipments,
    round(100.0 * count(*) / sum(count(*)) over (), 2) as share_of_exceptions_pct
from marts.fact_deliveries
where failure_reason is not null
group by failure_reason
order by affected_shipments desc;

-- Quality-rule counts. Counts overlap by design.
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
order by quality_rule;
