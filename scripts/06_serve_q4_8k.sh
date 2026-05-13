#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 06_serve_q4_8k.sh
# Run this ON THE RUNPOD POD, inside a tmux session.
#
# Starts vLLM with the Q4_K_M GGUF model, 8K context window.
# This is the FIRST configuration to test — lowest memory, fastest load.
#
# Usage:
#   tmux new -s vllm
#   bash /workspace/repo/scripts/06_serve_q4_8k.sh
#   (detach: Ctrl+B then D)
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Load environment ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then
    set -a; source "$REPO_ROOT/.env"; set +a
    echo "  ✓  Loaded .env"
else
    echo "  ✗  .env not found at $REPO_ROOT/.env — aborting."
    exit 1
fi

# Load config overrides for this specific profile
if [ -f "$REPO_ROOT/configs/q4_8k.env" ]; then
    set -a; source "$REPO_ROOT/configs/q4_8k.env"; set +a
fi

# ── Validate required variables ────────────────────────────────────────────
: "${Q4_MODEL_PATH:?'Q4_MODEL_PATH not set in .env'}"
: "${TOKENIZER_ID:?'TOKENIZER_ID not set in .env'}"
: "${VLLM_API_KEY:?'VLLM_API_KEY not set in .env'}"
: "${VLLM_HOST:?'VLLM_HOST not set in .env'}"
: "${VLLM_PORT:?'VLLM_PORT not set in .env'}"
: "${GPU_MEMORY_UTILIZATION:?'GPU_MEMORY_UTILIZATION not set in .env'}"
: "${SERVED_MODEL_NAME_Q4:?'SERVED_MODEL_NAME_Q4 not set in .env'}"

# ── Confirm model file exists ─────────────────────────────────────────────
if [ ! -f "$Q4_MODEL_PATH" ]; then
    echo ""
    echo "  ✗  Model file not found: $Q4_MODEL_PATH"
    echo "     Run 05_download_models.sh first."
    exit 1
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  Starting vLLM — Q4_K_M, 8K context"
echo "  Model   : $Q4_MODEL_PATH"
echo "  Endpoint: http://$VLLM_HOST:$VLLM_PORT"
echo "  Context : 8192 tokens"
echo "══════════════════════════════════════════════"
echo ""
echo "  Public URL: ${RUNPOD_PUBLIC_BASE_URL:-https://mv4dfc2mn9l8zc-8000.proxy.runpod.net}"
echo ""

# ── Launch vLLM ───────────────────────────────────────────────────────────
# VLLM_ROCM_USE_AITER=1 enables AMD's AITER kernel optimizations for MI300X,
# which can improve throughput significantly over the default CUDA-compat path.

VLLM_ROCM_USE_AITER=1 vllm serve "$Q4_MODEL_PATH" \
    \
    `# ── Model identity ───────────────────────────────────────────────────` \
    --served-model-name "$SERVED_MODEL_NAME_Q4" \
    \
    `# ── Tokenizer: must be specified for GGUF; points to the HF base model` \
    --tokenizer "$TOKENIZER_ID" \
    \
    `# ── Network ──────────────────────────────────────────────────────────` \
    --host "$VLLM_HOST" \
    --port "$VLLM_PORT" \
    \
    `# ── dtype: float16 required for GGUF models on ROCm ──────────────────` \
    --dtype float16 \
    \
    `# ── Context window: 8192 tokens (safe starting point) ────────────────` \
    --max-model-len 8192 \
    \
    `# ── VRAM fraction for KV cache (0.88 = 88%, leaves headroom) ─────────` \
    --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" \
    \
    `# ── Prefix caching: reuses KV cache for repeated prompt prefixes ──────` \
    --enable-prefix-caching \
    \
    `# ── API key authentication ────────────────────────────────────────────` \
    --api-key "$VLLM_API_KEY"
