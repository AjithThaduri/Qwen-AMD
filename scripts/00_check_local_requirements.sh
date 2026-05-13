#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 00_check_local_requirements.sh
# Run this on your MAC before anything else.
# It checks that the tools you need locally are installed.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo "  ✓  $name"
        PASS=$((PASS + 1))
    else
        echo "  ✗  $name  ← NOT FOUND"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "══════════════════════════════════════════════"
echo "  Local Mac requirements check"
echo "══════════════════════════════════════════════"
echo ""

# SSH client — should be pre-installed on every Mac
check "ssh" "command -v ssh"

# curl — for quick API tests without Python
check "curl" "command -v curl"

# Python 3.8+ — needed for test and benchmark scripts
check "python3 (3.8+)" "python3 -c 'import sys; assert sys.version_info >= (3,8)'"

# pip — Python package manager
check "pip3" "command -v pip3"

# openai Python package — used by test and benchmark scripts
check "openai Python package" "python3 -c 'import openai'"

# jq — pretty-print JSON API responses (optional but useful)
check "jq (optional)" "command -v jq"

echo ""
echo "══════════════════════════════════════════════"
echo "  Result: $PASS passed, $FAIL failed"
echo "══════════════════════════════════════════════"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo "Fix failures before proceeding:"
    echo ""
    echo "  Install openai package:"
    echo "    pip3 install openai"
    echo ""
    echo "  Install jq (optional):"
    echo "    brew install jq"
    echo ""
    exit 1
fi

echo "All required tools found. You are ready to connect to RunPod."
echo ""
echo "Next step: read scripts/01_connect_runpod_notes.md"
echo ""
