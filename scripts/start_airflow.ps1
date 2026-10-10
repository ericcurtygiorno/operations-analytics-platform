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

docker compose --env-file .env --profile airflow up -d postgres airflow
if ($LASTEXITCODE -ne 0) { throw "Airflow could not be started." }

$AirflowPort = "8080"
$PortLine = Get-Content .env | Select-String '^AIRFLOW_PORT=' | Select-Object -First 1
if ($PortLine) {
    $AirflowPort = $PortLine.Line.Split('=', 2)[1]
}

Write-Output "Airflow is starting at http://localhost:$AirflowPort."
Write-Output "Use 'docker compose --env-file .env logs airflow' to read the generated local credentials."
