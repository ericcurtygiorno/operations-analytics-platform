$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

if (-not (Test-Path -LiteralPath ".env")) {
    throw "Missing .env. Copy .env.example to .env and choose a local password."
}

Get-Content -LiteralPath ".env" | ForEach-Object {
    $line = $_.Trim()
    if ($line -and -not $line.StartsWith("#")) {
        $name, $value = $line -split "=", 2
        [Environment]::SetEnvironmentVariable($name, $value, "Process")
    }
}

docker compose --env-file .env up -d postgres
if ($LASTEXITCODE -ne 0) { throw "PostgreSQL container could not be started." }

$ready = $false
for ($attempt = 1; $attempt -le 20; $attempt++) {
    docker compose --env-file .env exec -T postgres `
        pg_isready -U $env:POSTGRES_USER -d $env:POSTGRES_DB *> $null
    if ($LASTEXITCODE -eq 0) {
        $ready = $true
        break
    }
    Start-Sleep -Seconds 2
}
if (-not $ready) { throw "PostgreSQL did not become ready." }

& ".\.venv\Scripts\python.exe" -m src.operations_analytics.generator `
    --config config/generator.json --output sample_data
if ($LASTEXITCODE -ne 0) { throw "Synthetic data generation failed." }

& ".\.venv\Scripts\python.exe" -m src.operations_analytics.ingestion `
    --input sample_data --env-file .env
if ($LASTEXITCODE -ne 0) { throw "Raw ingestion failed." }

& ".\.venv\Scripts\dbt.exe" build --profiles-dir dbt
if ($LASTEXITCODE -ne 0) { throw "dbt build failed." }

& ".\.venv\Scripts\python.exe" -m src.operations_analytics.evidence `
    --env-file .env `
    --run-results target/run_results.json `
    --output-dir artifacts/evidence `
    --docs-dir docs
if ($LASTEXITCODE -ne 0) { throw "Analytical evidence generation failed." }

Write-Output "Vertical slice and evidence generation completed successfully. Power BI schema: marts."
