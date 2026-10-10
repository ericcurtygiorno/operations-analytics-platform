"""Generate deterministic synthetic logistics data with intentional anomalies."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import random
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class GeneratorConfig:
    seed: int
    start_date: date
    end_date: date
    order_count: int
    anomaly_counts: dict[str, int]

    @classmethod
    def from_path(cls, path: Path) -> GeneratorConfig:
        payload = json.loads(path.read_text(encoding="utf-8"))
        start = date.fromisoformat(payload["start_date"])
        end = date.fromisoformat(payload["end_date"])
        order_count = int(payload["order_count"])
        if start > end:
            raise ValueError("start_date must not be after end_date")
        if order_count < 20:
            raise ValueError("order_count must be at least 20")
        return cls(
            seed=int(payload["seed"]),
            start_date=start,
            end_date=end,
            order_count=order_count,
            anomaly_counts={key: int(value) for key, value in payload["anomaly_counts"].items()},
        )


CARRIERS = ("Aurora Express", "BluePeak Logistics", "Cedar Freight", "Delta Parcel")
DISTRIBUTION_CENTERS = ("DC-SAO", "DC-REC", "DC-CWB")
REGIONS = ("Southeast", "South", "Northeast", "Central-West")
SERVICE_DAYS = {"express": 2, "standard": 4, "economy": 7}
EVENT_FAILURE_REASONS = ("weather", "address_issue", "capacity", "customer_unavailable")


def _iso(value: datetime | None) -> str:
    return value.isoformat(timespec="seconds") if value else ""


def _random_datetime(rng: random.Random, start: date, end: date) -> datetime:
    day_offset = rng.randint(0, (end - start).days)
    return datetime.combine(start + timedelta(days=day_offset), datetime.min.time()) + timedelta(
        hours=rng.randint(7, 20), minutes=rng.randint(0, 59)
    )


def _write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def _write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True, ensure_ascii=False) + "\n")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _select_indices(rng: random.Random, total: int, count: int, reserved: set[int]) -> list[int]:
    available = [index for index in range(total) if index not in reserved]
    if count > len(available):
        raise ValueError("Anomaly count exceeds the available clean records")
    selected = rng.sample(available, count)
    reserved.update(selected)
    return selected


def generate(config: GeneratorConfig, output_dir: Path) -> dict[str, Any]:
    """Generate source files and return the deterministic generation manifest."""

    rng = random.Random(config.seed)
    output_dir.mkdir(parents=True, exist_ok=True)
    batch_id = f"seed-{config.seed}"

    orders: list[dict[str, Any]] = []
    clean_order_ids: list[str] = []
    for number in range(1, config.order_count + 1):
        order_id = f"ORD-{number:06d}"
        clean_order_ids.append(order_id)
        order_at = _random_datetime(rng, config.start_date, config.end_date)
        quantity = rng.randint(1, 8)
        weight_kg = round(rng.uniform(0.3, 35.0), 2)
        region = rng.choice(REGIONS)
        service_type = rng.choices(tuple(SERVICE_DAYS), weights=(18, 57, 25), k=1)[0]
        orders.append(
            {
                "order_id": order_id,
                "customer_id": f"CUS-{rng.randint(1, max(40, config.order_count // 3)):05d}",
                "order_at": _iso(order_at),
                "distribution_center_id": rng.choice(DISTRIBUTION_CENTERS),
                "destination_region": region,
                "service_type": service_type,
                "quantity": quantity,
                "weight_kg": weight_kg,
                "freight_amount": round(8.5 + weight_kg * rng.uniform(0.75, 1.55), 2),
                "source_batch_id": batch_id,
            }
        )

    clean_orders = [dict(row) for row in orders]
    order_reserved: set[int] = set()
    for index in _select_indices(
        rng, len(orders), config.anomaly_counts.get("missing_order_id", 0), order_reserved
    ):
        orders[index]["order_id"] = ""
    for index in _select_indices(
        rng, len(orders), config.anomaly_counts.get("negative_quantity", 0), order_reserved
    ):
        orders[index]["quantity"] = -rng.randint(1, 4)
    duplicate_indices = rng.sample(
        range(len(orders)), config.anomaly_counts.get("duplicate_order", 0)
    )
    orders.extend(dict(orders[index]) for index in duplicate_indices)

    shipments: list[dict[str, Any]] = []
    events: list[dict[str, Any]] = []
    for number, (order_id, order) in enumerate(zip(clean_order_ids, clean_orders), start=1):
        order_at = datetime.fromisoformat(order["order_at"])
        shipped_at = order_at + timedelta(days=rng.randint(0, 3), hours=rng.randint(1, 8))
        promised_at = shipped_at + timedelta(days=SERVICE_DAYS[order["service_type"]])
        is_open = rng.random() < 0.08
        delay_days = rng.choices((-1, 0, 1, 2, 3, 5), weights=(8, 42, 20, 14, 10, 6), k=1)[0]
        delivered_at = None if is_open else promised_at + timedelta(days=delay_days)
        status = "in_transit" if is_open else "delivered"
        shipment_id = f"SHP-{number:06d}"
        carrier = rng.choice(CARRIERS)
        shipments.append(
            {
                "shipment_id": shipment_id,
                "order_id": order_id,
                "carrier_name": carrier,
                "shipped_at": _iso(shipped_at),
                "promised_delivery_at": _iso(promised_at),
                "delivered_at": _iso(delivered_at),
                "delivery_status": status,
                "delivery_attempts": (
                    0
                    if is_open
                    else rng.choices((1, 2, 3), weights=(84, 13, 3), k=1)[0]
                ),
                "source_batch_id": batch_id,
            }
        )
        events.append(
            {
                "event_id": f"EVT-{number:06d}-01",
                "shipment_id": shipment_id,
                "event_type": "shipped",
                "event_at": _iso(shipped_at),
                "failure_reason": None,
                "source_batch_id": batch_id,
            }
        )
        if delivered_at:
            if delay_days > 0:
                events.append(
                    {
                        "event_id": f"EVT-{number:06d}-02",
                        "shipment_id": shipment_id,
                        "event_type": "delivery_exception",
                        "event_at": _iso(promised_at),
                        "failure_reason": rng.choice(EVENT_FAILURE_REASONS),
                        "source_batch_id": batch_id,
                    }
                )
            events.append(
                {
                    "event_id": f"EVT-{number:06d}-03",
                    "shipment_id": shipment_id,
                    "event_type": "delivered",
                    "event_at": _iso(delivered_at),
                    "failure_reason": None,
                    "source_batch_id": batch_id,
                }
            )

    shipment_reserved: set[int] = set()
    for index in _select_indices(
        rng, len(shipments), config.anomaly_counts.get("unknown_carrier", 0), shipment_reserved
    ):
        shipments[index]["carrier_name"] = "Unknown Carrier"
    for index in _select_indices(
        rng,
        len(shipments),
        config.anomaly_counts.get("delivery_before_shipment", 0),
        shipment_reserved,
    ):
        shipped_at = datetime.fromisoformat(shipments[index]["shipped_at"])
        shipments[index]["delivered_at"] = _iso(shipped_at - timedelta(days=1))
        shipments[index]["delivery_status"] = "delivered"
    for index in _select_indices(
        rng,
        len(shipments),
        config.anomaly_counts.get("delivered_without_date", 0),
        shipment_reserved,
    ):
        shipments[index]["delivered_at"] = ""
        shipments[index]["delivery_status"] = "delivered"

    for offset in range(config.anomaly_counts.get("orphan_shipment", 0)):
        base = shipments[offset]
        orphan = dict(base)
        orphan["shipment_id"] = f"SHP-ORPHAN-{offset + 1:03d}"
        orphan["order_id"] = f"ORD-MISSING-{offset + 1:03d}"
        shipments.append(orphan)

    orders_path = output_dir / "orders.csv"
    shipments_path = output_dir / "shipments.csv"
    events_path = output_dir / "delivery_events.jsonl"
    _write_csv(orders_path, orders, list(orders[0]))
    _write_csv(shipments_path, shipments, list(shipments[0]))
    _write_jsonl(events_path, events)

    manifest = {
        "generator_version": "0.1.0",
        "seed": config.seed,
        "period": {
            "start_date": config.start_date.isoformat(),
            "end_date": config.end_date.isoformat(),
        },
        "row_counts": {
            "orders": len(orders),
            "shipments": len(shipments),
            "delivery_events": len(events),
        },
        "injected_anomalies": dict(sorted(config.anomaly_counts.items())),
        "files": {
            "orders.csv": _sha256(orders_path),
            "shipments.csv": _sha256(shipments_path),
            "delivery_events.jsonl": _sha256(events_path),
        },
    }
    with (output_dir / "generation_manifest.json").open(
        "w", encoding="utf-8", newline="\n"
    ) as handle:
        handle.write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    config = GeneratorConfig.from_path(args.config)
    manifest = generate(config, args.output)
    print(json.dumps(manifest["row_counts"], sort_keys=True))


if __name__ == "__main__":
    main()
