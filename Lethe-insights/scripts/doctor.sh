#!/usr/bin/env bash
# doctor.sh — Validate dev environment for Lethe Insights.
# Run from the Lethe-insights directory:  ./scripts/doctor.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OK=true

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}=== Lethe Doctor ===${NC}"

# --- Tool versions ---
echo ""
echo -e "${YELLOW}[Tools]${NC}"

if command -v node &>/dev/null; then
    NODE_V=$(node -v)
    echo -e "  Node.js    : ${GREEN}${NODE_V}${NC}"
    MAJOR=$(echo "$NODE_V" | sed 's/^v//' | cut -d. -f1)
    if [ "$MAJOR" -lt 20 ]; then
        echo -e "  ${RED}WARNING: Node >= 20 recommended (you have $MAJOR)${NC}"
        OK=false
    fi
else
    echo -e "  Node.js    : ${RED}NOT FOUND${NC}"
    OK=false
fi

if command -v npm &>/dev/null; then
    echo -e "  npm        : ${GREEN}$(npm -v)${NC}"
else
    echo -e "  npm        : ${RED}NOT FOUND${NC}"
    OK=false
fi

if command -v git &>/dev/null; then
    echo -e "  Git        : ${GREEN}$(git --version)${NC}"
else
    echo -e "  Git        : ${RED}NOT FOUND${NC}"
    OK=false
fi

if command -v supabase &>/dev/null; then
    echo -e "  Supabase   : ${GREEN}$(supabase --version)${NC}"
else
    echo -e "  Supabase   : ${YELLOW}not installed (optional)${NC}"
fi

# --- Dependencies ---
echo ""
echo -e "${YELLOW}[Dependencies]${NC}"

if [ -d "$ROOT/node_modules" ]; then
    echo -e "  node_modules: ${GREEN}present${NC}"
else
    echo -e "  node_modules: ${RED}MISSING — run 'npm install'${NC}"
    OK=false
fi

if [ -f "$ROOT/package-lock.json" ]; then
    echo -e "  lockfile   : ${GREEN}present${NC}"
else
    echo -e "  lockfile   : ${RED}MISSING${NC}"
fi

# --- Environment variables ---
echo ""
echo -e "${YELLOW}[Environment]${NC}"

ENV_FILE="$ROOT/.env.local"
REQUIRED_VARS=(
    "VITE_SUPABASE_URL"
    "VITE_SUPABASE_ANON_KEY"
    "VITE_MAPBOX_TOKEN"
)

if [ -f "$ENV_FILE" ]; then
    echo -e "  .env.local : ${GREEN}found${NC}"

    for v in "${REQUIRED_VARS[@]}"; do
        VAL=$(grep -E "^${v}\s*=" "$ENV_FILE" | head -1 | sed "s/^${v}\s*=\s*//")
        if [ -z "$VAL" ]; then
            echo -e "  ${v} : ${RED}MISSING from .env.local${NC}"
            OK=false
        elif echo "$VAL" | grep -qE "PLACEHOLDER|YOUR_"; then
            echo -e "  ${v} : ${RED}PLACEHOLDER (needs real value)${NC}"
            OK=false
        else
            MASKED="${VAL:0:8}..."
            echo -e "  ${v} : ${GREEN}${MASKED}${NC}"
        fi
    done
else
    echo -e "  .env.local : ${RED}NOT FOUND${NC}"
    echo "  Run: cp .env.example .env.local"
    OK=false
fi

# --- Summary ---
echo ""
if $OK; then
    echo -e "${GREEN}All checks passed. Start the app with:${NC}"
    echo "  npm run dev"
else
    echo -e "${RED}Some checks failed. Fix the issues above and re-run.${NC}"
    echo "  ./scripts/doctor.sh"
fi
echo ""
