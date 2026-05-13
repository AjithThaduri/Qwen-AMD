#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 06_serve_awq_8k.sh
# Run this ON THE RUNPOD POD, inside a tmux session.
#
# Starts vLLM with INT4 AWQ model, 8K context window.
# Uses Triton-based AWQ kernels (ROCm compatible).
#
# Usage:
#   tmux new -s vllm
#   bash /workspace/repo/scripts/06_serve_awq_8k.sh
#   Detach: Ctrl+B then D
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then
    set -a; source "$REPO_ROOT/.env"; set +a
    echo "  ✓  Loaded .env"
else
    echo "  ✗  .env not found — aborting."; exit 1
fi

: "${AWQ_MODEL_DIR:?'AWQ_MODEL_DIR not set in .env'}"
: "${SERVED_MODEL_NAME_AWQ:?'SERVED_MODEL_NAME_AWQ not set in .env'}"
: "${VLLM_API_KEY:?'VLLM_API_KEY not set in .env'}"
: "${VLLM_HOST:?'VLLM_HOST not set in .env'}"
: "${VLLM_PORT:?'VLLM_PORT not set in .env'}"
: "${GPU_MEMORY_UTILIZATION:?'GPU_MEMORY_UTILIZATION not set in .env'}"

if [ ! -d "$AWQ_MODEL_DIR" ] || [ -z "$(ls -A "$AWQ_MODEL_DIR" 2>/dev/null)" ]; then
    echo "  ✗  Model not found at $AWQ_MODEL_DIR"
    echo "     Run 05_download_awq.sh first."
    exit 1
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  Starting vLLM — INT4 AWQ, 8K context"
echo "  Model   : $AWQ_MODEL_DIR"
echo "  Name    : $SERVED_MODEL_NAME_AWQ"
echo "  Endpoint: http://$VLLM_HOST:$VLLM_PORT"
echo "══════════════════════════════════════════════"
echo ""
echo "  Public URL: ${RUNPOD_PUBLIC_BASE_URL:-https://mv4dfc2mn9l8zc-8000.proxy.runpod.net}"
echo ""

# VLLM_TARGET_DEVICE=rocm   — tells vLLM to use ROCm/HIP path
# VLLM_ROCM_USE_AITER=1     — AMD MI300X AITER kernel optimizations
# AWQ quantization is detected automatically from the model's config.json

VLLM_TARGET_DEVICE=rocm VLLM_ROCM_USE_AITER=1 vllm serve "$AWQ_MODEL_DIR" \
    --served-model-name "$SERVED_MODEL_NAME_AWQ" \
    --host "$VLLM_HOST" \
    --port "$VLLM_PORT" \
    --dtype float16 \
    --quantization awq_marlin \
    --max-model-len 8192 \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    --enable-prefix-caching \
    --api-key "$VLLM_API_KEY"
