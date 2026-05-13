#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 10_serve_fp8_8k.sh
# FP8 model from Hugging Face (Qwen/Qwen3-30B-A3B-FP8), 8K context.
# This loads the model directly from HF — no local GGUF needed.
#
# Requires HF_TOKEN if the repo is gated.
# FP8 is the recommended format for native vLLM performance on MI300X.
# Test this AFTER you have Q4/Q5 baseline numbers.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then set -a; source "$REPO_ROOT/.env"; set +a; fi
if [ -f "$REPO_ROOT/configs/fp8_8k.env" ]; then set -a; source "$REPO_ROOT/configs/fp8_8k.env"; set +a; fi

: "${FP8_MODEL_ID:?'FP8_MODEL_ID not set'}"; : "${VLLM_API_KEY:?}"
: "${VLLM_HOST:?}"; : "${VLLM_PORT:?}"; : "${GPU_MEMORY_UTILIZATION:?}"; : "${SERVED_MODEL_NAME_FP8:?}"

# ── Set HF token if provided ──────────────────────────────────────────────
if [ -n "${HF_TOKEN:-}" ]; then
    export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
fi

echo ""
echo "═══════════════════════════════════════════════"
echo "  Starting vLLM — FP8 (HF), 8K context"
echo "  Model : $FP8_MODEL_ID"
echo "═══════════════════════════════════════════════"
echo ""

# Note: --dtype auto lets vLLM detect FP8 natively.
# --reasoning-parser qwen3 enables structured reasoning output.
# --trust-remote-code is required for Qwen3 custom code in the HF repo.

VLLM_ROCM_USE_AITER=1 vllm serve "$FP8_MODEL_ID" \
    --served-model-name "$SERVED_MODEL_NAME_FP8" \
    --host "$VLLM_HOST" \
    --port "$VLLM_PORT" \
    --dtype auto \
    --max-model-len 8192 \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    --enable-prefix-caching \
    --reasoning-parser qwen3 \
    --trust-remote-code \
    --api-key "$VLLM_API_KEY"
