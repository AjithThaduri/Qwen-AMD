#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 08_serve_q5_8k.sh
# Q5_K_M GGUF (~21.7 GB) with 8K context window.
# Higher quality than Q4; test after Q4 baseline is established.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then set -a; source "$REPO_ROOT/.env"; set +a; fi
if [ -f "$REPO_ROOT/configs/q5_8k.env" ]; then set -a; source "$REPO_ROOT/configs/q5_8k.env"; set +a; fi

: "${Q5_MODEL_PATH:?'Q5_MODEL_PATH not set'}"; : "${TOKENIZER_ID:?}"; : "${VLLM_API_KEY:?}"
: "${VLLM_HOST:?}"; : "${VLLM_PORT:?}"; : "${GPU_MEMORY_UTILIZATION:?}"; : "${SERVED_MODEL_NAME_Q5:?}"

if [ ! -f "$Q5_MODEL_PATH" ]; then echo "✗ Model not found: $Q5_MODEL_PATH"; exit 1; fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  Starting vLLM — Q5_K_M, 8K context"
echo "  Model : $Q5_MODEL_PATH"
echo "═══════════════════════════════════════════════"
echo ""

VLLM_ROCM_USE_AITER=1 vllm serve "$Q5_MODEL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME_Q5" \
    --tokenizer "$TOKENIZER_ID" \
    --host "$VLLM_HOST" \
    --port "$VLLM_PORT" \
    --dtype float16 \
    --max-model-len 8192 \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    --enable-prefix-caching \
    --api-key "$VLLM_API_KEY"
