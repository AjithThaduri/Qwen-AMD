#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 12_test_models_endpoint.sh
# Run this from your MAC after vLLM is started on the pod.
# Tests GET /v1/models to confirm the server is up and the model is loaded.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Load environment ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then
    set -a; source "$REPO_ROOT/.env"; set +a
else
    echo "✗ .env not found. Copy .env.example to .env and fill in your values."
    exit 1
fi

: "${RUNPOD_PUBLIC_BASE_URL:?'RUNPOD_PUBLIC_BASE_URL not set in .env'}"
: "${VLLM_API_KEY:?'VLLM_API_KEY not set in .env'}"

echo ""
echo "══════════════════════════════════════════════"
echo "  Testing /v1/models endpoint"
echo "  URL: $RUNPOD_PUBLIC_BASE_URL/v1/models"
echo "══════════════════════════════════════════════"
echo ""

# ── Test 1: Health check ───────────────────────────────────────────────────
echo "→ Health check (/health)..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "$RUNPOD_PUBLIC_BASE_URL/health" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✓  Server is healthy (HTTP 200)"
else
    echo "  ✗  Health check returned HTTP $HTTP_CODE"
    echo "     Is vLLM running? Check: tmux attach -t vllm"
    exit 1
fi
echo ""

# ── Test 2: List models ────────────────────────────────────────────────────
echo "→ GET /v1/models..."
echo ""

RESPONSE=$(curl -s \
    -H "Authorization: Bearer $VLLM_API_KEY" \
    "$RUNPOD_PUBLIC_BASE_URL/v1/models")

echo "$RESPONSE"
echo ""

# Pretty-print if jq is available
if command -v jq &>/dev/null; then
    echo "── Formatted response ───────────────────────"
    echo "$RESPONSE" | jq .
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  If you see a model in the list above, the"
echo "  server is ready for inference requests."
echo "  Next: run 13_test_chat_non_stream.py"
echo "══════════════════════════════════════════════"
echo ""
