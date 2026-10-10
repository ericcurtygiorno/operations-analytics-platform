$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Test-Path -LiteralPath ".env")) {
    throw "Missing .env. Copy .env.example to .env and choose a local password."
}

docker compose --env-file .env --profile pipeline build pipeline
if ($LASTEXITCODE -ne 0) { throw "Pipeline image build failed." }

docker compose --env-file .env up -d postgres
if ($LASTEXITCODE -ne 0) { throw "PostgreSQL container could not be started." }

docker compose --env-file .env --profile pipeline run --rm pipeline
if ($LASTEXITCODE -ne 0) { throw "Containerized pipeline failed." }

Write-Output "Containerized pipeline completed successfully."
