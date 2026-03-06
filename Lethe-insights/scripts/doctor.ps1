# doctor.ps1 — Validate dev environment for Lethe Insights.
# Run from the Lethe-insights directory:  .\scripts\doctor.ps1

$ErrorActionPreference = "SilentlyContinue"
$root = Split-Path -Parent $PSScriptRoot
$ok = $true

Write-Host "`n=== Lethe Doctor ===" -ForegroundColor Cyan

# --- Tool versions ---
Write-Host "`n[Tools]" -ForegroundColor Yellow

$nodeV = & node -v 2>$null
if ($nodeV) {
    Write-Host "  Node.js    : $nodeV" -ForegroundColor Green
    $major = [int]($nodeV -replace '^v','').Split('.')[0]
    if ($major -lt 20) {
        Write-Host "  WARNING: Node >= 20 recommended (you have $major)" -ForegroundColor Red
        $ok = $false
    }
} else {
    Write-Host "  Node.js    : NOT FOUND" -ForegroundColor Red
    $ok = $false
}

$npmV = & npm -v 2>$null
if ($npmV) {
    Write-Host "  npm        : $npmV" -ForegroundColor Green
} else {
    Write-Host "  npm        : NOT FOUND" -ForegroundColor Red
    $ok = $false
}

$gitV = & git --version 2>$null
if ($gitV) {
    Write-Host "  Git        : $gitV" -ForegroundColor Green
} else {
    Write-Host "  Git        : NOT FOUND" -ForegroundColor Red
    $ok = $false
}

$supaV = & supabase --version 2>$null
if ($supaV) {
    Write-Host "  Supabase   : $supaV" -ForegroundColor Green
} else {
    Write-Host "  Supabase   : not installed (optional)" -ForegroundColor DarkYellow
}

# --- Dependencies ---
Write-Host "`n[Dependencies]" -ForegroundColor Yellow
$nmPath = Join-Path $root "node_modules"
if (Test-Path $nmPath) {
    Write-Host "  node_modules: present" -ForegroundColor Green
} else {
    Write-Host "  node_modules: MISSING — run 'npm install'" -ForegroundColor Red
    $ok = $false
}

$lockPath = Join-Path $root "package-lock.json"
if (Test-Path $lockPath) {
    Write-Host "  lockfile   : present" -ForegroundColor Green
} else {
    Write-Host "  lockfile   : MISSING" -ForegroundColor Red
}

# --- Environment variables ---
Write-Host "`n[Environment]" -ForegroundColor Yellow

$requiredVars = @(
    "VITE_SUPABASE_URL",
    "VITE_SUPABASE_ANON_KEY",
    "VITE_MAPBOX_TOKEN"
)

$envFile = Join-Path $root ".env.local"
$envFound = Test-Path $envFile

if ($envFound) {
    Write-Host "  .env.local : found" -ForegroundColor Green
    $envContent = Get-Content $envFile -Raw

    foreach ($v in $requiredVars) {
        if ($envContent -match "(?m)^$v\s*=\s*.+") {
            $val = ($envContent | Select-String "(?m)^$v\s*=\s*(.+)").Matches[0].Groups[1].Value.Trim()
            if ($val -match "PLACEHOLDER|YOUR_") {
                Write-Host "  $v : PLACEHOLDER (needs real value)" -ForegroundColor Red
                $ok = $false
            } else {
                $masked = $val.Substring(0, [Math]::Min(8, $val.Length)) + "..."
                Write-Host "  $v : $masked" -ForegroundColor Green
            }
        } else {
            Write-Host "  $v : MISSING from .env.local" -ForegroundColor Red
            $ok = $false
        }
    }
} else {
    Write-Host "  .env.local : NOT FOUND" -ForegroundColor Red
    Write-Host "  Run: Copy-Item .env.example .env.local" -ForegroundColor White
    $ok = $false
}

# --- Summary ---
Write-Host ""
if ($ok) {
    Write-Host "All checks passed. Start the app with:" -ForegroundColor Green
    Write-Host "  npm run dev" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "Some checks failed. Fix the issues above and re-run." -ForegroundColor Red
    Write-Host '  .\scripts\doctor.ps1' -ForegroundColor White
    Write-Host ""
}
