from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path

from src.operations_analytics.generator import GeneratorConfig, generate

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = PROJECT_ROOT / "config" / "generator.json"


class GeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.config = GeneratorConfig.from_path(CONFIG_PATH)

    def test_generation_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_path = Path(first)
            second_path = Path(second)
            first_manifest = generate(self.config, first_path)
            second_manifest = generate(self.config, second_path)
            self.assertEqual(first_manifest, second_manifest)
            for filename in (*first_manifest["files"], "generation_manifest.json"):
                self.assertEqual(
                    (first_path / filename).read_bytes(), (second_path / filename).read_bytes()
                )

    def test_configured_anomalies_are_present(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            generate(self.config, output)
            with (output / "orders.csv").open(encoding="utf-8", newline="") as handle:
                orders = list(csv.DictReader(handle))
            with (output / "shipments.csv").open(encoding="utf-8", newline="") as handle:
                shipments = list(csv.DictReader(handle))

            order_ids = [row["order_id"] for row in orders if row["order_id"]]
            duplicates = len(order_ids) - len(set(order_ids))
            self.assertGreaterEqual(duplicates, self.config.anomaly_counts["duplicate_order"])
            self.assertEqual(
                sum(not row["order_id"] for row in orders),
                self.config.anomaly_counts["missing_order_id"],
            )
            self.assertEqual(
                sum(int(row["quantity"]) < 0 for row in orders),
                self.config.anomaly_counts["negative_quantity"],
            )
            self.assertEqual(
                sum(row["carrier_name"] == "Unknown Carrier" for row in shipments),
                self.config.anomaly_counts["unknown_carrier"],
            )
            self.assertEqual(
                sum(
                    row["delivery_status"] == "delivered" and not row["delivered_at"]
                    for row in shipments
                ),
                self.config.anomaly_counts["delivered_without_date"],
            )
            self.assertEqual(
                sum(row["order_id"].startswith("ORD-MISSING-") for row in shipments),
                self.config.anomaly_counts["orphan_shipment"],
            )

    def test_json_events_and_manifest_are_valid(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = generate(self.config, output)
            events = [
                json.loads(line)
                for line in (output / "delivery_events.jsonl")
                .read_text(encoding="utf-8")
                .splitlines()
            ]
            persisted_manifest = json.loads(
                (output / "generation_manifest.json").read_text(encoding="utf-8")
            )
            self.assertEqual(len(events), manifest["row_counts"]["delivery_events"])
            self.assertEqual(persisted_manifest, manifest)
            self.assertTrue(all(event["shipment_id"] for event in events))


if __name__ == "__main__":
    unittest.main()
