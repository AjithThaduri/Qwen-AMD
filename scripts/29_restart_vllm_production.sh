#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 29_restart_vllm_production.sh
# Run this ON THE RUNPOD POD after benchmark/capability testing is complete.
#
# Applies tuned production settings based on observed benchmark behaviour.
#
# Production settings (edit these to tune after testing):
#   max-model-len      : 16384  — 16K context balances UX and KV cache capacity
#   gpu-memory-utilization: 0.88 — headroom for spikes before VRAM alert fires
#   max-num-seqs       : 128    — conservative for stable concurrent serving
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── TUNE THESE after reviewing benchmark results ────────────────────────────
MAX_MODEL_LEN=16384           # tokens: 16K covers 95%+ of real-world requests
GPU_MEM_UTIL=0.88             # 88% of 192 GB ≈ 169 GB; leaves ~23 GB headroom
MAX_NUM_SEQS=128              # max concurrent requests in flight
# ─────────────────────────────────────────────────────────────────────────────

ts() { date '+%H:%M:%S'; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Restarting vLLM — PRODUCTION settings"
echo "  max-model-len    : ${MAX_MODEL_LEN} tokens"
echo "  gpu-memory-util  : ${GPU_MEM_UTIL}"
echo "  max-num-seqs     : ${MAX_NUM_SEQS}"
echo "══════════════════════════════════════════════════════"
echo ""

# ── stop current session ──────────────────────────────────────────────────────

if tmux has-session -t vllm 2>/dev/null; then
    echo "[$(ts)] Stopping vLLM..."
    tmux send-keys -t vllm C-c 2>/dev/null || true
    sleep 3
    tmux kill-session -t vllm 2>/dev/null || true
fi
pkill -f 'vllm serve' 2>/dev/null || true
sleep 2

# ── source environment ────────────────────────────────────────────────────────

source /workspace/vllm_rocm_env.sh

# ── start production vLLM ────────────────────────────────────────────────────

tmux new-session -d -s vllm -x 220 -y 50

SERVE_CMD="source /workspace/vllm_rocm_env.sh && vllm serve /workspace/models/awq \
     --served-model-name qwen3.6-35b-a3b-awq \
     --host 0.0.0.0 --port 8000 \
     --max-model-len ${MAX_MODEL_LEN} \
     --gpu-memory-utilization ${GPU_MEM_UTIL} \
     --max-num-seqs ${MAX_NUM_SEQS} \
     --trust-remote-code \
     --api-key dev-test-key \
     2>&1 | tee /workspace/serve_awq.log"

tmux send-keys -t vllm "$SERVE_CMD" Enter

# Also update the persistent auto-start script to use these production settings
cat > /workspace/start_vllm.sh << HEREDOC
#!/bin/bash
LOG=/workspace/autostart_vllm.log
echo "[\$(date)] autostart triggered" >> \$LOG

if tmux has-session -t vllm 2>/dev/null; then
    echo "[\$(date)] session already exists — skipping" >> \$LOG
    exit 0
fi

source /workspace/vllm_rocm_env.sh >> \$LOG 2>&1
tmux new-session -d -s vllm -x 220 -y 50
tmux send-keys -t vllm \\
    "source /workspace/vllm_rocm_env.sh && vllm serve /workspace/models/awq \\
     --served-model-name qwen3.6-35b-a3b-awq \\
     --host 0.0.0.0 --port 8000 \\
     --max-model-len ${MAX_MODEL_LEN} \\
     --gpu-memory-utilization ${GPU_MEM_UTIL} \\
     --max-num-seqs ${MAX_NUM_SEQS} \\
     --trust-remote-code \\
     --api-key dev-test-key \\
     2>&1 | tee /workspace/serve_awq.log" Enter

echo "[\$(date)] vllm session started (production: len=${MAX_MODEL_LEN})" >> \$LOG
HEREDOC
chmod +x /workspace/start_vllm.sh
echo "[$(ts)] Updated /workspace/start_vllm.sh with production settings."

# ── wait for ready ────────────────────────────────────────────────────────────

echo "[$(ts)] Waiting for server (up to 3 min)..."
for i in $(seq 1 36); do
    sleep 5
    if curl -sf http://localhost:8000/health &>/dev/null; then
        echo ""
        echo "[$(ts)] ✓ vLLM is up — PRODUCTION settings active."
        echo ""
        echo "  max-model-len : ${MAX_MODEL_LEN}"
        echo "  gpu-mem-util  : ${GPU_MEM_UTIL}"
        echo "  max-num-seqs  : ${MAX_NUM_SEQS}"
        echo ""
        echo "  Auto-start /workspace/start_vllm.sh updated with these settings."
        exit 0
    fi
    echo -n "."
done

echo ""
echo "[$(ts)] Timed out — check: tmux attach -t vllm"
exit 1
