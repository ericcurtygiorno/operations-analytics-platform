$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Test-Path -LiteralPath ".env")) {
    throw "Missing .env. Copy .env.example to .env and choose a local password."
}

docker compose --env-file .env --profile airflow build airflow
if ($LASTEXITCODE -ne 0) { throw "Airflow image build failed." }

docker compose --env-file .env --profile airflow run --rm airflow-init
if ($LASTEXITCODE -ne 0) { throw "Airflow metadata volume initialization failed." }

docker compose --env-file .env up -d postgres
if ($LASTEXITCODE -ne 0) { throw "PostgreSQL container could not be started." }

docker compose --env-file .env --profile airflow run --rm airflow `
    bash -c "airflow db migrate && airflow dags list-import-errors --output json && airflow dags test operations_analytics_pipeline 2026-10-09"
if ($LASTEXITCODE -ne 0) { throw "Airflow DAG validation failed." }

Write-Output "Airflow DAG parsed and executed successfully."
