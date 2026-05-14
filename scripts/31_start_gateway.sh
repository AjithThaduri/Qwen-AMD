#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 31_start_gateway.sh
# Run this ON THE RUNPOD POD.
# Starts the FastAPI API gateway in the 'vllm:gateway' tmux window.
# Gateway listens on port 8080 and proxies to vLLM on port 8000.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT="/workspace/scripts/30_api_gateway.py"
STATS_DIR="/workspace/gateway_stats"
LOG="${STATS_DIR}/gateway.log"
PORT=8080

ts() { date '+%H:%M:%S'; }

mkdir -p "$STATS_DIR"

# Install deps if missing
source /workspace/vllm_rocm_env.sh 2>/dev/null
pip install -q fastapi uvicorn httpx 2>/dev/null || true

# Kill any existing gateway process
pkill -f "30_api_gateway" 2>/dev/null || true
sleep 1

# Check vLLM is up before starting gateway
if ! curl -sf http://localhost:8000/health &>/dev/null; then
    echo "[$(ts)] ERROR: vLLM is not running on port 8000. Start it first."
    echo "  bash /workspace/scripts/19_start_vllm_tmux.sh"
    exit 1
fi

# Start in tmux window 'gateway' inside the 'vllm' session
if tmux has-session -t vllm 2>/dev/null; then
    # Create new window if it doesn't exist
    tmux new-window -t vllm -n gateway 2>/dev/null || true
    tmux send-keys -t vllm:gateway \
        "source /workspace/vllm_rocm_env.sh && cd /workspace/scripts && python3 30_api_gateway.py 2>&1 | tee ${LOG}" \
        Enter
else
    # Fallback: create a new session
    tmux new-session -d -s gateway -x 220 -y 50
    tmux send-keys -t gateway \
        "source /workspace/vllm_rocm_env.sh && cd /workspace/scripts && python3 30_api_gateway.py 2>&1 | tee ${LOG}" \
        Enter
fi

echo "[$(ts)] Gateway starting in tmux (vllm:gateway)..."
echo ""

# Wait for port to open
for i in $(seq 1 20); do
    sleep 2
    if curl -sf http://localhost:${PORT}/health &>/dev/null; then
        echo "[$(ts)] ✓ Gateway is up on port ${PORT}"
        echo ""
        echo "  ┌─────────────────────────────────────────────────────────────┐"
        echo "  │  API Keys                                                   │"
        echo "  │  Dev   : sk-qwen-dev-xK9mP2nL                              │"
        echo "  │  Prod  : sk-qwen-prod-rT5jW8vQ                             │"
        echo "  │  Spare : sk-qwen-spare-hN3cA6yD                            │"
        echo "  ├─────────────────────────────────────────────────────────────┤"
        echo "  │  Endpoint  : http://localhost:${PORT}/v1                      │"
        echo "  │  Health    : http://localhost:${PORT}/health                  │"
        echo "  │  Usage     : http://localhost:${PORT}/v1/usage                │"
        echo "  │  Log       : ${LOG}                  │"
        echo "  └─────────────────────────────────────────────────────────────┘"
        echo ""
        exit 0
    fi
    echo -n "."
done

echo ""
echo "[$(ts)] Timed out. Check: tmux attach -t vllm:gateway"
exit 1
