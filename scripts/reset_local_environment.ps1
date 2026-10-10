param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Split-Path -Parent $PSScriptRoot)).Path
Set-Location $ProjectRoot

if (-not $Force) {
    throw "Reset removes the project PostgreSQL and Airflow metadata volumes. Re-run with -Force after confirming this is intended."
}

$ComposeFile = (Resolve-Path (Join-Path $ProjectRoot "docker-compose.yml")).Path
if (-not $ComposeFile.StartsWith($ProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Compose file escaped the project root."
}

docker compose --env-file .env --profile pipeline --profile airflow down --volumes --remove-orphans
if ($LASTEXITCODE -ne 0) { throw "Local environment reset failed." }

Write-Output "Project containers and the PostgreSQL and Airflow metadata volumes were removed."
