$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

docker compose --env-file .env --profile airflow stop airflow
if ($LASTEXITCODE -ne 0) { throw "Airflow could not be stopped." }

Write-Output "Airflow stopped; its local metadata volume was preserved."
