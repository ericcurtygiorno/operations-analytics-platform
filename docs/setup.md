# Local Setup

## Prerequisites

- Docker Desktop with the Linux container engine running.
- PowerShell 7 for the helper scripts.
- Power BI Desktop only when opening the dashboard locally.

Python, dbt, and PostgreSQL command-line tools are not required on the host when using the fully
containerized flow.

## First-time configuration

From the project root:

```powershell
Copy-Item .env.example .env
```

Replace the example PostgreSQL password in `.env` with a local development password. The `.env`
file is ignored by Git and must never be committed.

## Recommended containerized run

```powershell
.\scripts\run_containerized_pipeline.ps1
```

The script:

1. builds the Python/dbt pipeline image;
2. starts PostgreSQL and waits for its health check;
3. generates the deterministic source bundle;
4. performs idempotent raw ingestion;
5. builds staging, intermediate, and mart models;
6. executes all dbt tests;
7. regenerates analytical and quality evidence;
8. removes the one-off pipeline container while preserving PostgreSQL data.

The database is exposed at `localhost:55432` for Power BI Desktop. Containers connect internally
through the Compose service name `postgres` on port `5432`.

## Host-Python alternative

For development and debugging:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[analytics]"
Copy-Item .env.example .env
.\scripts\run_vertical_slice.ps1
```

This alternative still runs PostgreSQL in Docker but executes generation, ingestion, dbt, and
evidence creation in the local virtual environment.

## Stop without deleting data

```powershell
.\scripts\stop_local_database.ps1
```

## Reset the project database

Reset is intentionally explicit because it deletes the project PostgreSQL volume:

```powershell
.\scripts\reset_local_environment.ps1 -Force
```

Only synthetic, reproducible project data belongs in this volume. Run the containerized pipeline
again to rebuild the environment from zero.

## Power BI

Open `dashboard/operations-analytics-platform.pbip` after a successful pipeline run. The local
connection is PostgreSQL database `operations_analytics` at `localhost:55432`; use the credentials
from the local `.env` file.

## Airflow orchestration

Validate the real DAG and its complete task chain:

```powershell
.\scripts\run_airflow_validation.ps1
```

Start the local Airflow UI when you want to inspect or manually trigger the DAG:

```powershell
.\scripts\start_airflow.ps1
```

The default address is `http://localhost:8080`. Read the generated local credentials with
`docker compose --env-file .env logs airflow`. See [orchestration](orchestration.md) for scheduling,
parameters, retries, and the local-runtime trade-off.

Stop Airflow without deleting its metadata:

```powershell
.\scripts\stop_airflow.ps1
```
