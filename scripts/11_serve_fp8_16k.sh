#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 11_serve_fp8_16k.sh
# FP8 model from Hugging Face, 16K context.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then set -a; source "$REPO_ROOT/.env"; set +a; fi
if [ -f "$REPO_ROOT/configs/fp8_16k.env" ]; then set -a; source "$REPO_ROOT/configs/fp8_16k.env"; set +a; fi

: "${FP8_MODEL_ID:?}"; : "${VLLM_API_KEY:?}"; : "${VLLM_HOST:?}"; : "${VLLM_PORT:?}"
: "${GPU_MEMORY_UTILIZATION:?}"; : "${SERVED_MODEL_NAME_FP8:?}"

if [ -n "${HF_TOKEN:-}" ]; then export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"; fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  Starting vLLM — FP8 (HF), 16K context"
echo "  Model : $FP8_MODEL_ID"
echo "═══════════════════════════════════════════════"
echo ""

VLLM_ROCM_USE_AITER=1 vllm serve "$FP8_MODEL_ID" \
    --served-model-name "$SERVED_MODEL_NAME_FP8" \
    --host "$VLLM_HOST" \
    --port "$VLLM_PORT" \
    --dtype auto \
    --max-model-len 16384 \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    --enable-prefix-caching \
    --reasoning-parser qwen3 \
    --trust-remote-code \
    --api-key "$VLLM_API_KEY"
