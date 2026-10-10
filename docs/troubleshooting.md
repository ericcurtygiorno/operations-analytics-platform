# Troubleshooting

## Docker engine is unavailable

Symptom: the client cannot connect to `dockerDesktopLinuxEngine`.

1. Start Docker Desktop.
2. Wait until the Linux engine reports that it is running.
3. Verify with `docker info`.
4. Re-run the project script.

If Docker reports a WSL resource error, restart Windows first. Then confirm that WSL and Docker
Desktop start normally before changing project configuration.

## PostgreSQL does not become healthy

Inspect the service without exposing credentials:

```powershell
docker compose --env-file .env ps
docker compose --env-file .env logs postgres
```

Common causes are an invalid `.env`, port `55432` already in use, or a damaged local development
volume. Use the reset command only when deleting the synthetic project database is acceptable.

## Port 55432 is already in use

Choose another host port in `.env`, for example:

```text
POSTGRES_PORT=55433
```

The pipeline container still uses the internal PostgreSQL port `5432`. Update the Power BI local
connection if the host port changes.

## Ingestion returns `skipped`

This is expected for an already completed deterministic load. The manifest hash produces the same
`load_id`, and the ingestion layer avoids duplicating raw rows. Change the generator configuration
or seed only when a genuinely new source batch is intended.

## dbt fails a test

The pipeline stops before evidence generation. Review the failed test name and inspect:

- `target/run_results.json` for machine-readable status;
- the relevant model YAML for generic tests;
- `dbt/tests` for custom business rules;
- raw ingestion metadata to confirm the selected completed load.

Do not bypass a failing critical test to refresh Power BI. Resolve or explicitly document the data
contract or business-rule decision first.

## Power BI cannot connect

1. Confirm PostgreSQL is healthy with `docker compose --env-file .env ps`.
2. Confirm the host and port match the `.env` file.
3. Use PostgreSQL credentials from `.env`; do not place them in screenshots or documentation.
4. Run the pipeline once so the `marts` schema exists.

## Clean rebuild

For synthetic local data only:

```powershell
.\scripts\reset_local_environment.ps1 -Force
.\scripts\run_containerized_pipeline.ps1
```

The reset command is scoped to this Compose project and removes its containers plus the PostgreSQL
and Airflow metadata named volumes.

## Airflow cannot write its metadata or logs

Run the provided startup or validation script instead of starting the service with an isolated
`docker run` command. Both scripts execute `airflow-init`, which grants the non-root Airflow user
access to the named metadata volume.

If the volume was created by an older configuration, re-run:

```powershell
docker compose --env-file .env --profile airflow run --rm airflow-init
```

## The DAG is not visible

Check import errors and the effective DAG folder:

```powershell
docker compose --env-file .env --profile airflow run --rm airflow `
  bash -c "airflow db migrate && airflow dags list-import-errors --output json"
```

An empty JSON list means no import error was found. The Compose configuration mounts
`orchestration/dags` at `/opt/project/orchestration/dags`.

## An Airflow task fails

The task retains the failed state after two retries, emits the failed task and run identifiers, and
blocks downstream tasks. Inspect the task log first. Then execute the matching component directly:

- generation: `python -m src.operations_analytics.generator ...`;
- ingestion: `python -m src.operations_analytics.ingestion ...`;
- transformation and quality: `dbt build --profiles-dir dbt`;
- evidence: `python -m src.operations_analytics.evidence ...`.

Fix the underlying component rather than marking the task successful manually.
