from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from src.operations_analytics.generator import GeneratorConfig, generate
from src.operations_analytics.ingestion import read_source_bundle

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = PROJECT_ROOT / "config" / "generator.json"


class IngestionContractTests(unittest.TestCase):
    def test_source_bundle_matches_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = generate(GeneratorConfig.from_path(CONFIG_PATH), output)
            bundle = read_source_bundle(output)
            self.assertEqual(len(bundle.orders), manifest["row_counts"]["orders"])
            self.assertEqual(len(bundle.shipments), manifest["row_counts"]["shipments"])
            self.assertEqual(len(bundle.events), manifest["row_counts"]["delivery_events"])
            self.assertTrue(bundle.load_id.startswith("load-"))

    def test_manifest_line_endings_do_not_change_load_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            generate(GeneratorConfig.from_path(CONFIG_PATH), output)
            manifest_path = output / "generation_manifest.json"
            original_bundle = read_source_bundle(output)
            content = manifest_path.read_text(encoding="utf-8")
            manifest_path.write_bytes(content.replace("\r\n", "\n").replace("\n", "\r\n").encode())
            windows_bundle = read_source_bundle(output)

            self.assertEqual(original_bundle.load_id, windows_bundle.load_id)

    def test_checksum_mismatch_stops_ingestion(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            generate(GeneratorConfig.from_path(CONFIG_PATH), output)
            orders_path = output / "orders.csv"
            orders_path.write_text(
                orders_path.read_text(encoding="utf-8") + "tampered\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "Checksum mismatch for orders.csv"):
                read_source_bundle(output)

    def test_invalid_json_stops_ingestion_after_checksum_is_updated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            generate(GeneratorConfig.from_path(CONFIG_PATH), output)
            events_path = output / "delivery_events.jsonl"
            events_path.write_text("not-json\n", encoding="utf-8")
            manifest_path = output / "generation_manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            import hashlib

            manifest["files"]["delivery_events.jsonl"] = hashlib.sha256(
                events_path.read_bytes()
            ).hexdigest()
            manifest["row_counts"]["delivery_events"] = 1
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Invalid JSON"):
                read_source_bundle(output)


if __name__ == "__main__":
    unittest.main()
