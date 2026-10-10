import json
import tempfile
import unittest
from pathlib import Path

from src.operations_analytics.evidence import summarize_dbt_results


class DbtEvidenceTests(unittest.TestCase):
    def test_summarizes_successful_dbt_build(self) -> None:
        payload = {
            "metadata": {"generated_at": "2026-10-09T12:00:00Z"},
            "results": [
                {"unique_id": "model.project.fact_deliveries", "status": "success"},
                {"unique_id": "test.project.unique_fact", "status": "pass"},
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run_results.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            result = summarize_dbt_results(path)

        self.assertEqual(result["total_nodes"], 2)
        self.assertEqual(result["statuses"], {"pass": 1, "success": 1})
        self.assertEqual(result["resource_types"], {"model": 1, "test": 1})
        self.assertTrue(result["all_passed"])

    def test_marks_failed_dbt_build(self) -> None:
        payload = {
            "metadata": {},
            "results": [{"unique_id": "test.project.rule", "status": "fail"}],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "run_results.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            result = summarize_dbt_results(path)

        self.assertFalse(result["all_passed"])


if __name__ == "__main__":
    unittest.main()
