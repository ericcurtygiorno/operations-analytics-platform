"""Load synthetic source files into traceable PostgreSQL raw tables."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import psycopg2
from psycopg2.extras import Json, execute_values

ORDER_COLUMNS = (
    "order_id",
    "customer_id",
    "order_at",
    "distribution_center_id",
    "destination_region",
    "service_type",
    "quantity",
    "weight_kg",
    "freight_amount",
    "source_batch_id",
)
SHIPMENT_COLUMNS = (
    "shipment_id",
    "order_id",
    "carrier_name",
    "shipped_at",
    "promised_delivery_at",
    "delivered_at",
    "delivery_status",
    "delivery_attempts",
    "source_batch_id",
)
EVENT_COLUMNS = (
    "event_id",
    "shipment_id",
    "event_type",
    "event_at",
    "failure_reason",
    "source_batch_id",
)


SCHEMA_SQL = """
create schema if not exists raw;

create table if not exists raw.ingestion_batches (
    load_id text primary key,
    source_batch_id text not null,
    manifest_hash text not null,
    status text not null check (status in ('running', 'completed')),
    row_counts jsonb not null,
    file_hashes jsonb not null,
    started_at timestamptz not null default now(),
    completed_at timestamptz
);

create table if not exists raw.orders (
    _raw_id bigint generated always as identity primary key,
    order_id text,
    customer_id text,
    order_at text,
    distribution_center_id text,
    destination_region text,
    service_type text,
    quantity text,
    weight_kg text,
    freight_amount text,
    source_batch_id text,
    _ingested_at timestamptz not null default now(),
    _source_file text not null,
    _source_file_hash text not null,
    _source_row_number integer not null,
    _load_id text not null references raw.ingestion_batches(load_id),
    unique (_source_file_hash, _source_row_number)
);

create table if not exists raw.shipments (
    _raw_id bigint generated always as identity primary key,
    shipment_id text,
    order_id text,
    carrier_name text,
    shipped_at text,
    promised_delivery_at text,
    delivered_at text,
    delivery_status text,
    delivery_attempts text,
    source_batch_id text,
    _ingested_at timestamptz not null default now(),
    _source_file text not null,
    _source_file_hash text not null,
    _source_row_number integer not null,
    _load_id text not null references raw.ingestion_batches(load_id),
    unique (_source_file_hash, _source_row_number)
);

create table if not exists raw.delivery_events (
    _raw_id bigint generated always as identity primary key,
    event_id text,
    shipment_id text,
    event_type text,
    event_at text,
    failure_reason text,
    source_batch_id text,
    _payload jsonb not null,
    _ingested_at timestamptz not null default now(),
    _source_file text not null,
    _source_file_hash text not null,
    _source_row_number integer not null,
    _load_id text not null references raw.ingestion_batches(load_id),
    unique (_source_file_hash, _source_row_number)
);
"""


@dataclass(frozen=True)
class DatabaseConfig:
    host: str
    port: int
    dbname: str
    user: str
    password: str

    @classmethod
    def from_environment(cls) -> DatabaseConfig:
        required = (
            "POSTGRES_HOST",
            "POSTGRES_PORT",
            "POSTGRES_DB",
            "POSTGRES_USER",
            "POSTGRES_PASSWORD",
        )
        missing = [name for name in required if not os.getenv(name)]
        if missing:
            raise ValueError(f"Missing database settings: {', '.join(missing)}")
        return cls(
            host=os.environ["POSTGRES_HOST"],
            port=int(os.environ["POSTGRES_PORT"]),
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["POSTGRES_USER"],
            password=os.environ["POSTGRES_PASSWORD"],
        )


@dataclass(frozen=True)
class SourceBundle:
    manifest: dict[str, Any]
    manifest_hash: str
    load_id: str
    orders: list[dict[str, Any]]
    shipments: list[dict[str, Any]]
    events: list[dict[str, Any]]


def load_env_file(path: Path) -> None:
    """Load simple KEY=VALUE settings without overwriting the current environment."""

    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _canonical_manifest_hash(manifest: dict[str, Any]) -> str:
    """Hash manifest content independently of operating-system line endings."""

    canonical = json.dumps(manifest, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _read_csv(path: Path, expected_columns: tuple[str, ...]) -> list[dict[str, Any]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        if tuple(reader.fieldnames or ()) != expected_columns:
            raise ValueError(f"Unexpected columns in {path.name}: {reader.fieldnames}")
        return list(reader)


def _read_jsonl(path: Path, expected_columns: tuple[str, ...]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON in {path.name} line {line_number}") from exc
        if tuple(sorted(row)) != tuple(sorted(expected_columns)):
            raise ValueError(f"Unexpected fields in {path.name} line {line_number}")
        rows.append(row)
    return rows


def read_source_bundle(input_dir: Path) -> SourceBundle:
    manifest_path = input_dir / "generation_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_hash = _canonical_manifest_hash(manifest)
    paths = {
        "orders.csv": input_dir / "orders.csv",
        "shipments.csv": input_dir / "shipments.csv",
        "delivery_events.jsonl": input_dir / "delivery_events.jsonl",
    }
    for filename, path in paths.items():
        actual_hash = _sha256(path)
        expected_hash = manifest["files"][filename]
        if actual_hash != expected_hash:
            raise ValueError(f"Checksum mismatch for {filename}")

    orders = _read_csv(paths["orders.csv"], ORDER_COLUMNS)
    shipments = _read_csv(paths["shipments.csv"], SHIPMENT_COLUMNS)
    events = _read_jsonl(paths["delivery_events.jsonl"], EVENT_COLUMNS)
    actual_counts = {
        "orders": len(orders),
        "shipments": len(shipments),
        "delivery_events": len(events),
    }
    if actual_counts != manifest["row_counts"]:
        raise ValueError(f"Row counts do not match manifest: {actual_counts}")
    return SourceBundle(
        manifest=manifest,
        manifest_hash=manifest_hash,
        load_id=f"load-{manifest_hash[:16]}",
        orders=orders,
        shipments=shipments,
        events=events,
    )


def _raw_rows(
    rows: Iterable[dict[str, Any]],
    columns: tuple[str, ...],
    source_file: str,
    file_hash: str,
    load_id: str,
    include_payload: bool = False,
) -> list[tuple[Any, ...]]:
    prepared: list[tuple[Any, ...]] = []
    for row_number, row in enumerate(rows, start=2 if source_file.endswith(".csv") else 1):
        values: tuple[Any, ...] = tuple(row[column] for column in columns)
        if include_payload:
            values += (Json(row),)
        prepared.append(values + (source_file, file_hash, row_number, load_id))
    return prepared


def ingest(input_dir: Path, config: DatabaseConfig) -> dict[str, Any]:
    bundle = read_source_bundle(input_dir)
    file_hashes = bundle.manifest["files"]
    connection = psycopg2.connect(
        host=config.host,
        port=config.port,
        dbname=config.dbname,
        user=config.user,
        password=config.password,
    )
    try:
        with connection:
            with connection.cursor() as cursor:
                cursor.execute(SCHEMA_SQL)
                cursor.execute(
                    """
                    select batches.load_id
                    from raw.ingestion_batches batches
                    where batches.status = 'completed'
                      and batches.file_hashes = %s
                      and exists (
                          select 1 from raw.orders rows where rows._load_id = batches.load_id
                      )
                      and exists (
                          select 1 from raw.shipments rows where rows._load_id = batches.load_id
                      )
                      and exists (
                          select 1
                          from raw.delivery_events rows
                          where rows._load_id = batches.load_id
                      )
                    order by batches.completed_at desc, batches.load_id desc
                    limit 1
                    """,
                    (Json(file_hashes),),
                )
                reusable = cursor.fetchone()
                if reusable:
                    return {
                        "load_id": reusable[0],
                        "status": "skipped",
                        **bundle.manifest["row_counts"],
                    }
                cursor.execute(
                    "select status from raw.ingestion_batches where load_id = %s",
                    (bundle.load_id,),
                )
                existing = cursor.fetchone()
                if existing and existing[0] == "completed":
                    return {
                        "load_id": bundle.load_id,
                        "status": "skipped",
                        **bundle.manifest["row_counts"],
                    }

                cursor.execute(
                    """
                    insert into raw.ingestion_batches
                        (load_id, source_batch_id, manifest_hash, status, row_counts, file_hashes)
                    values (%s, %s, %s, 'running', %s, %s)
                    on conflict (load_id) do update set
                        status = 'running', started_at = now(), completed_at = null
                    """,
                    (
                        bundle.load_id,
                        f"seed-{bundle.manifest['seed']}",
                        bundle.manifest_hash,
                        Json(bundle.manifest["row_counts"]),
                        Json(file_hashes),
                    ),
                )
                execute_values(
                    cursor,
                    """
                    insert into raw.orders (
                        order_id, customer_id, order_at, distribution_center_id,
                        destination_region, service_type, quantity, weight_kg,
                        freight_amount, source_batch_id, _source_file,
                        _source_file_hash, _source_row_number, _load_id
                    ) values %s on conflict (_source_file_hash, _source_row_number) do nothing
                    """,
                    _raw_rows(
                        bundle.orders,
                        ORDER_COLUMNS,
                        "orders.csv",
                        file_hashes["orders.csv"],
                        bundle.load_id,
                    ),
                )
                execute_values(
                    cursor,
                    """
                    insert into raw.shipments (
                        shipment_id, order_id, carrier_name, shipped_at,
                        promised_delivery_at, delivered_at, delivery_status,
                        delivery_attempts, source_batch_id, _source_file,
                        _source_file_hash, _source_row_number, _load_id
                    ) values %s on conflict (_source_file_hash, _source_row_number) do nothing
                    """,
                    _raw_rows(
                        bundle.shipments,
                        SHIPMENT_COLUMNS,
                        "shipments.csv",
                        file_hashes["shipments.csv"],
                        bundle.load_id,
                    ),
                )
                execute_values(
                    cursor,
                    """
                    insert into raw.delivery_events (
                        event_id, shipment_id, event_type, event_at, failure_reason,
                        source_batch_id, _payload, _source_file, _source_file_hash,
                        _source_row_number, _load_id
                    ) values %s on conflict (_source_file_hash, _source_row_number) do nothing
                    """,
                    _raw_rows(
                        bundle.events,
                        EVENT_COLUMNS,
                        "delivery_events.jsonl",
                        file_hashes["delivery_events.jsonl"],
                        bundle.load_id,
                        include_payload=True,
                    ),
                )
                cursor.execute(
                    """
                    update raw.ingestion_batches
                    set status = 'completed', completed_at = now()
                    where load_id = %s
                    """,
                    (bundle.load_id,),
                )
        return {"load_id": bundle.load_id, "status": "loaded", **bundle.manifest["row_counts"]}
    finally:
        connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=Path("sample_data"))
    parser.add_argument("--env-file", type=Path, default=Path(".env"))
    args = parser.parse_args()
    load_env_file(args.env_file)
    result = ingest(args.input, DatabaseConfig.from_environment())
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
