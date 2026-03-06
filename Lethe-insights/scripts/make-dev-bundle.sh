#!/usr/bin/env bash
# make-dev-bundle.sh — Create a portable ZIP of the Lethe-insights project.
# Run from the Lethe-insights directory:  ./scripts/make-dev-bundle.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP_NAME="lethe-dev-bundle.zip"
ZIP_PATH="$ROOT/$ZIP_NAME"

echo ""
echo "=== Lethe Dev Bundle ==="

INCLUDES=(
    src
    public
    sql
    docs
    scripts
    package.json
    package-lock.json
    vite.config.ts
    tsconfig.json
    tsconfig.app.json
    tsconfig.node.json
    eslint.config.js
    index.html
    .env.example
    README.md
    DEV-NOTES.md
)

EXCLUDES=(
    "node_modules/*"
    "dist/*"
    ".git/*"
    ".env"
    ".env.local"
    ".env.*.local"
    "*.log"
)

echo ""
echo "Excluding:"
for ex in "${EXCLUDES[@]}"; do
    echo "  - $ex"
done

# Build the zip, only including items that exist
cd "$ROOT"

# Remove old zip if exists
rm -f "$ZIP_PATH"

INCLUDED=()
SKIPPED=()

for item in "${INCLUDES[@]}"; do
    if [ -e "$item" ]; then
        INCLUDED+=("$item")
    else
        SKIPPED+=("$item")
    fi
done

# Build exclude flags for zip
EXCLUDE_FLAGS=()
for ex in "${EXCLUDES[@]}"; do
    EXCLUDE_FLAGS+=(-x "$ex")
done

if [ ${#INCLUDED[@]} -gt 0 ]; then
    zip -r "$ZIP_PATH" "${INCLUDED[@]}" "${EXCLUDE_FLAGS[@]}" -q
fi

echo ""
echo "Included:"
for inc in "${INCLUDED[@]}"; do
    echo "  + $inc"
done

if [ ${#SKIPPED[@]} -gt 0 ]; then
    echo ""
    echo "Skipped (not found):"
    for sk in "${SKIPPED[@]}"; do
        echo "  ~ $sk"
    done
fi

SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo ""
echo "Bundle created: $ZIP_PATH ($SIZE)"
echo "Transfer this ZIP to your new PC, extract, then run:"
echo "  npm install"
echo "  Copy your .env.local into the folder"
echo "  npm run dev"
echo ""
