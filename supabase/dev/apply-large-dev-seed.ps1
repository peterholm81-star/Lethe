Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$seedFile = Join-Path $repoRoot "supabase\dev\large_dev_seed.sql"

if (-not (Test-Path $seedFile)) {
  throw "Seed file not found: $seedFile"
}

$containerName = "supabase_db_Confess"
$container = docker ps --filter "name=$containerName" --format "{{.Names}}" | Select-Object -First 1

if (-not $container) {
  throw @"
Local Supabase database container is not running.

Start local Supabase first:
  npx supabase start
  npm run supabase:dev:reset

Then run:
  npm run supabase:dev:seed-large
"@
}

Write-Host "Applying DEV-ONLY large seed to local Supabase container: $containerName"
Write-Host "This does not touch hosted/production Supabase projects."

Get-Content -Raw $seedFile | docker exec -i $containerName psql -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) {
  throw "Large dev seed failed with exit code $LASTEXITCODE"
}

Write-Host "Large dev seed applied."
