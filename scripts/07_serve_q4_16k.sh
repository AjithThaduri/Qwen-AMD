#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 07_serve_q4_16k.sh
# Q4_K_M GGUF with 16K context window.
# Run AFTER 06_serve_q4_8k.sh has been tested successfully.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then set -a; source "$REPO_ROOT/.env"; set +a; fi
if [ -f "$REPO_ROOT/configs/q4_16k.env" ]; then set -a; source "$REPO_ROOT/configs/q4_16k.env"; set +a; fi

: "${Q4_MODEL_PATH:?'Q4_MODEL_PATH not set'}"; : "${TOKENIZER_ID:?}"; : "${VLLM_API_KEY:?}"
: "${VLLM_HOST:?}"; : "${VLLM_PORT:?}"; : "${GPU_MEMORY_UTILIZATION:?}"; : "${SERVED_MODEL_NAME_Q4:?}"

if [ ! -f "$Q4_MODEL_PATH" ]; then echo "✗ Model not found: $Q4_MODEL_PATH"; exit 1; fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  Starting vLLM — Q4_K_M, 16K context"
echo "  Model : $Q4_MODEL_PATH"
echo "═══════════════════════════════════════════════"
echo ""

VLLM_ROCM_USE_AITER=1 vllm serve "$Q4_MODEL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME_Q4" \
    --tokenizer "$TOKENIZER_ID" \
    --host "$VLLM_HOST" \
    --port "$VLLM_PORT" \
    --dtype float16 \
    --max-model-len 16384 \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    --enable-prefix-caching \
    --api-key "$VLLM_API_KEY"
