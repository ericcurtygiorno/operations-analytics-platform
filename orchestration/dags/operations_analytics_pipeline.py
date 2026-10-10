"""Orchestrate the real Operations Analytics Platform vertical slice."""

from __future__ import annotations

import logging
import os
import subprocess
from datetime import timedelta
from pathlib import Path

import pendulum
from airflow.sdk import DAG, Param, get_current_context, task

DAG_ID = "operations_analytics_pipeline"
PROJECT_ROOT = Path(os.environ.get("OAP_PROJECT_ROOT", "/opt/project")).resolve()
PIPELINE_PYTHON = os.environ.get("PIPELINE_PYTHON", "/opt/pipeline-venv/bin/python")
DBT_BINARY = os.environ.get("DBT_BINARY", "/opt/pipeline-venv/bin/dbt")


def _project_path(relative_path: str) -> Path:
    """Resolve a runtime parameter without allowing it outside the project checkout."""

    candidate = (PROJECT_ROOT / relative_path).resolve()
    if not candidate.is_relative_to(PROJECT_ROOT):
        raise ValueError(f"Path must remain inside {PROJECT_ROOT}: {relative_path}")
    return candidate


def _run(command: list[str]) -> None:
    """Run one real pipeline component and stream its output into Airflow logs."""

    logging.info("Running: %s", " ".join(command))
    subprocess.run(command, cwd=PROJECT_ROOT, check=True, env=os.environ.copy())


def _log_failure(context: dict) -> None:
    """Add an actionable failure record while preserving Airflow's failed state."""

    task_instance = context.get("task_instance")
    exception = context.get("exception")
    logging.error(
        "Pipeline failure: dag=%s task=%s run=%s error=%s",
        DAG_ID,
        getattr(task_instance, "task_id", "unknown"),
        context.get("run_id", "unknown"),
        exception,
    )


with DAG(
    dag_id=DAG_ID,
    description="Generate, ingest, transform, test, and publish logistics analytics evidence.",
    schedule="0 6 * * *",
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    max_active_runs=1,
    default_args={
        "owner": "data-platform",
        "retries": 2,
        "retry_delay": timedelta(minutes=2),
        "execution_timeout": timedelta(minutes=20),
        "on_failure_callback": _log_failure,
    },
    params={
        "generator_config": Param(
            "config/generator.json",
            type="string",
            description="Generator configuration relative to the project root.",
        ),
        "source_directory": Param(
            "sample_data",
            type="string",
            description="Source bundle directory relative to the project root.",
        ),
    },
    tags=["portfolio", "logistics", "dbt", "quality"],
) as dag:

    @task(task_id="generate_source_bundle")
    def generate_source_bundle() -> None:
        params = get_current_context()["params"]
        config_path = _project_path(params["generator_config"])
        source_directory = _project_path(params["source_directory"])
        _run(
            [
                PIPELINE_PYTHON,
                "-m",
                "src.operations_analytics.generator",
                "--config",
                str(config_path),
                "--output",
                str(source_directory),
            ]
        )

    @task(task_id="ingest_raw_batch")
    def ingest_raw_batch() -> None:
        params = get_current_context()["params"]
        source_directory = _project_path(params["source_directory"])
        _run(
            [
                PIPELINE_PYTHON,
                "-m",
                "src.operations_analytics.ingestion",
                "--input",
                str(source_directory),
                "--env-file",
                str(PROJECT_ROOT / ".env"),
            ]
        )

    @task(task_id="build_and_test_dbt")
    def build_and_test_dbt() -> None:
        _run([DBT_BINARY, "build", "--profiles-dir", str(PROJECT_ROOT / "dbt")])

    @task(task_id="publish_analysis_evidence")
    def publish_analysis_evidence() -> None:
        _run(
            [
                PIPELINE_PYTHON,
                "-m",
                "src.operations_analytics.evidence",
                "--env-file",
                str(PROJECT_ROOT / ".env"),
                "--run-results",
                str(PROJECT_ROOT / "target/run_results.json"),
                "--output-dir",
                str(PROJECT_ROOT / "artifacts/evidence"),
                "--docs-dir",
                str(PROJECT_ROOT / "docs"),
            ]
        )

    (
        generate_source_bundle()
        >> ingest_raw_batch()
        >> build_and_test_dbt()
        >> publish_analysis_evidence()
    )
