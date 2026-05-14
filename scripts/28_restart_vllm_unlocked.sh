#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 28_restart_vllm_unlocked.sh
# Run this ON THE RUNPOD POD.
#
# Restarts vLLM with full-capability settings for benchmarking & capability
# testing. Removes the conservative 8192-token context cap.
#
# After testing, run 29_restart_vllm_production.sh to apply production limits.
#
# Unlocked settings vs production defaults:
#   max-model-len      : 32768  (was 8192)  — Qwen3 supports up to 128K
#   gpu-memory-utilization: 0.92 (was 0.85) — more VRAM for KV cache
#   max-num-seqs       : 256    (default)   — concurrent request capacity
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

LOG=/workspace/autostart_vllm.log
ts() { date '+%H:%M:%S'; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Restarting vLLM — UNLOCKED (testing mode)"
echo "  max-model-len      : 32768 tokens"
echo "  gpu-memory-util    : 0.92  (92% of 192 GB = ~177 GB)"
echo "  Context avail      : 32768 tokens input+output"
echo "══════════════════════════════════════════════════════"
echo ""

# ── kill current vLLM ────────────────────────────────────────────────────────

if tmux has-session -t vllm 2>/dev/null; then
    echo "[$(ts)] Stopping existing vLLM tmux session..."
    tmux send-keys -t vllm C-c 2>/dev/null || true
    sleep 3
    # Kill the whole session — we'll recreate it
    tmux kill-session -t vllm 2>/dev/null || true
    echo "[$(ts)] Old session killed."
else
    echo "[$(ts)] No existing tmux session — starting fresh."
fi

# Also kill any leftover vllm serve processes
pkill -f 'vllm serve' 2>/dev/null || true
sleep 2

# ── source environment ────────────────────────────────────────────────────────

source /workspace/vllm_rocm_env.sh

# ── start vLLM unlocked ───────────────────────────────────────────────────────

echo "[$(ts)] Creating new tmux session 'vllm' ..."
tmux new-session -d -s vllm -x 220 -y 50

SERVE_CMD="source /workspace/vllm_rocm_env.sh && vllm serve /workspace/models/awq \
     --served-model-name qwen3.6-35b-a3b-awq \
     --host 0.0.0.0 --port 8000 \
     --max-model-len 32768 \
     --gpu-memory-utilization 0.92 \
     --max-num-seqs 256 \
     --trust-remote-code \
     --api-key dev-test-key \
     2>&1 | tee /workspace/serve_awq.log"

tmux send-keys -t vllm "$SERVE_CMD" Enter

echo "[$(ts)] vLLM starting in tmux session 'vllm' (unlocked settings)."
echo ""
echo "Waiting for server to become ready (up to 3 min)..."
for i in $(seq 1 36); do
    sleep 5
    if curl -sf http://localhost:8000/health &>/dev/null; then
        echo ""
        echo "[$(ts)] ✓ vLLM is up and healthy!"
        echo ""
        echo "  Endpoint : http://localhost:8000/v1"
        echo "  Context  : 32768 tokens  (4× previous 8192)"
        echo "  VRAM cap : 92%  (~177 GB)"
        echo ""
        echo "Run benchmarks:"
        echo "  bash /workspace/scripts/24_bench_vllm_serve.sh"
        echo ""
        echo "When done, restore production limits:"
        echo "  bash /workspace/scripts/29_restart_vllm_production.sh"
        echo ""
        echo "[$(ts)] vLLM log: tmux attach -t vllm"
        exit 0
    fi
    echo -n "."
done

echo ""
echo "[$(ts)] Timed out waiting for /health. Check: tmux attach -t vllm"
exit 1
