# Airflow Orchestration

## Purpose

The `operations_analytics_pipeline` DAG orchestrates the same real components used by the verified
command-line workflow. It is intentionally not a display-only DAG.

```text
generate_source_bundle
        ↓
ingest_raw_batch
        ↓
build_and_test_dbt
        ↓
publish_analysis_evidence
```

The pipeline runs daily at 06:00 UTC, does not backfill historical schedules, and allows only one
active run. Every task has two retries, a two-minute retry delay, a twenty-minute timeout, and an
actionable failure log. A failed command keeps the task failed and blocks downstream work.

## Runtime parameters

- `generator_config`: generator configuration relative to the project root;
- `source_directory`: source bundle directory relative to the project root.

Both parameters are validated to remain inside the project checkout. Commands are executed as
argument lists without shell interpolation.

## Local architecture

The Airflow container uses Airflow `3.3.2` and a dedicated Python virtual environment for dbt and
pipeline dependencies. This isolates Airflow's own dependency graph from the analytics runtime.
For a lightweight local portfolio environment, `airflow standalone` and `LocalExecutor` are
used. This is sufficient to demonstrate scheduling, dependencies, parameters, retries, logging,
and failure propagation; it is not presented as a production-scale deployment.

PostgreSQL remains the analytics database. Airflow's local metadata is stored in its own named
volume and is not exposed to Power BI. An initialization service grants the non-root Airflow user
access to that volume before the application starts.

## Validate the DAG end to end

```powershell
.\scripts\run_airflow_validation.ps1
```

The command builds the Airflow image, checks for import errors, and executes a complete test DAG run
against the real PostgreSQL service.

## Open the local Airflow UI

```powershell
.\scripts\start_airflow.ps1
```

Open `http://localhost:8080`. The standalone service writes generated local credentials to its
container log. The DAG is paused when first created so that an intentional manual review precedes
scheduled execution.
