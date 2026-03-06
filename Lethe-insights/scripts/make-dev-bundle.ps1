# make-dev-bundle.ps1 — Create a portable ZIP of the Lethe-insights project.
# Run from the Lethe-insights directory:  .\scripts\make-dev-bundle.ps1

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot   # Lethe-insights folder
$zipName = "lethe-dev-bundle.zip"
$zipPath = Join-Path $root $zipName
$tempDir = Join-Path $env:TEMP "lethe-dev-bundle-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

Write-Host "`n=== Lethe Dev Bundle ===" -ForegroundColor Cyan

# Folders/files to include (relative to repo root)
$includes = @(
    "src",
    "public",
    "sql",
    "docs",
    "scripts",
    "package.json",
    "package-lock.json",
    "vite.config.ts",
    "tsconfig.json",
    "tsconfig.app.json",
    "tsconfig.node.json",
    "eslint.config.js",
    "index.html",
    ".env.example",
    "README.md",
    "DEV-NOTES.md"
)

# Patterns to always exclude
$excludes = @(
    "node_modules",
    "dist",
    ".git",
    ".env",
    ".env.local",
    ".env.*.local",
    "*.log"
)

Write-Host "`nExcluding:" -ForegroundColor Yellow
$excludes | ForEach-Object { Write-Host "  - $_" }

# Create temp staging directory
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

$included = @()
$skipped = @()

foreach ($item in $includes) {
    $source = Join-Path $root $item
    $dest = Join-Path $tempDir $item

    if (-not (Test-Path $source)) {
        $skipped += $item
        continue
    }

    if ((Get-Item $source).PSIsContainer) {
        Copy-Item -Path $source -Destination $dest -Recurse -Force
        $included += "$item/ (directory)"
    } else {
        $parentDir = Split-Path $dest -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        Copy-Item -Path $source -Destination $dest -Force
        $included += $item
    }
}

Write-Host "`nIncluded:" -ForegroundColor Green
$included | ForEach-Object { Write-Host "  + $_" }

if ($skipped.Count -gt 0) {
    Write-Host "`nSkipped (not found):" -ForegroundColor DarkYellow
    $skipped | ForEach-Object { Write-Host "  ~ $_" }
}

# Remove zip if it already exists
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

# Create ZIP
Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath -Force

# Cleanup
Remove-Item $tempDir -Recurse -Force

$sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
Write-Host "`nBundle created: $zipPath ($sizeMB MB)" -ForegroundColor Cyan
Write-Host "Transfer this ZIP to your new PC, extract, then run:" -ForegroundColor White
Write-Host "  npm install" -ForegroundColor White
Write-Host "  Copy your .env.local into the folder" -ForegroundColor White
Write-Host "  npm run dev`n" -ForegroundColor White
