#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 32_start_production.sh
# Run this ON THE RUNPOD POD.
#
# Starts the full production stack:
#   1. vLLM on port 8001 (internal)  — tmux window: vllm:server
#   2. Gateway on port 8000 (public) — tmux window: vllm:gateway
#   3. Watchdog loop                 — tmux window: vllm:watchdog
#
# Public URL: https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1
#
# Watchdog restarts vLLM and gateway automatically if either crashes.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

LOG=/workspace/autostart_vllm.log
GATEWAY_LOG=/workspace/gateway_stats/gateway.log
STATS_DIR=/workspace/gateway_stats

mkdir -p "$STATS_DIR"
ts() { date '+%H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }

echo ""
echo "══════════════════════════════════════════════════════"
echo "  Qwen3 Production Stack Startup"
echo "  vLLM  : port 8001 (internal)"
echo "  Gateway: port 8000 (public → RunPod proxy)"
echo "  URL   : https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1"
echo "══════════════════════════════════════════════════════"
echo ""

# ── 0. Clean up any existing sessions ────────────────────────────────────────

log "Stopping existing services..."
pkill -f 'vllm serve'      2>/dev/null || true
pkill -f '30_api_gateway'  2>/dev/null || true
tmux kill-server           2>/dev/null || true
sleep 3

# ── 1. Source environment ─────────────────────────────────────────────────────

source /workspace/vllm_rocm_env.sh
pip install -q fastapi uvicorn httpx 2>/dev/null || true

# ── 2. Create tmux session ────────────────────────────────────────────────────

log "Creating tmux session 'vllm'..."
tmux new-session -d -s vllm -n server -x 220 -y 50

# ── 3. Start vLLM on port 8001 ────────────────────────────────────────────────

VLLM_CMD="source /workspace/vllm_rocm_env.sh && \
vllm serve /workspace/models/awq \
  --served-model-name qwen3.6-35b-a3b-awq \
  --host 0.0.0.0 --port 8001 \
  --max-model-len 16384 \
  --gpu-memory-utilization 0.80 \
  --max-num-seqs 100 \
  --trust-remote-code \
  --api-key dev-test-key \
  2>&1 | tee /workspace/serve_awq.log"

tmux send-keys -t vllm:server "$VLLM_CMD" Enter
log "vLLM starting on port 8001..."

# ── 4. Wait for vLLM to be healthy ───────────────────────────────────────────

log "Waiting for vLLM to become ready (up to 8 min)..."
READY=0
for i in $(seq 1 96); do
    sleep 5
    if curl -sf http://localhost:8001/health &>/dev/null; then
        READY=1
        break
    fi
    [[ $((i % 6)) -eq 0 ]] && log "  still loading... (~$((i*5))s elapsed)"
done

if [[ $READY -eq 0 ]]; then
    log "ERROR: vLLM did not start in time. Check: tmux attach -t vllm:server"
    exit 1
fi
log "✓ vLLM is healthy on port 8001"

# ── 5. Start gateway on port 8000 ─────────────────────────────────────────────

tmux new-window -t vllm -n gateway
GATEWAY_CMD="source /workspace/vllm_rocm_env.sh && \
cd /workspace/scripts && python3 30_api_gateway.py 2>&1 | tee ${GATEWAY_LOG}"

tmux send-keys -t vllm:gateway "$GATEWAY_CMD" Enter
log "Gateway starting on port 8000..."

for i in $(seq 1 15); do
    sleep 2
    if curl -sf http://localhost:8000/health &>/dev/null; then
        log "✓ Gateway is healthy on port 8000"
        break
    fi
done

# ── 6. Start watchdog ─────────────────────────────────────────────────────────

tmux new-window -t vllm -n watchdog
WATCHDOG_CMD='
while true; do
  sleep 30
  # Check vLLM
  if ! curl -sf http://localhost:8001/health &>/dev/null; then
    echo "[$(date +%H:%M:%S)] WATCHDOG: vLLM down — restarting..."
    pkill -f "vllm serve" 2>/dev/null || true
    sleep 2
    source /workspace/vllm_rocm_env.sh
    nohup vllm serve /workspace/models/awq \
      --served-model-name qwen3.6-35b-a3b-awq \
      --host 0.0.0.0 --port 8001 \
      --max-model-len 16384 \
      --gpu-memory-utilization 0.80 \
      --max-num-seqs 100 \
      --trust-remote-code \
      --api-key dev-test-key \
      >> /workspace/serve_awq.log 2>&1 &
    echo "[$(date +%H:%M:%S)] WATCHDOG: vLLM restarted (PID $!)"
    # Wait for vLLM before restarting gateway
    for i in $(seq 1 96); do
      sleep 5
      curl -sf http://localhost:8001/health &>/dev/null && break
    done
  fi
  # Check gateway
  if ! curl -sf http://localhost:8000/health &>/dev/null; then
    echo "[$(date +%H:%M:%S)] WATCHDOG: Gateway down — restarting..."
    pkill -f "30_api_gateway" 2>/dev/null || true
    sleep 2
    source /workspace/vllm_rocm_env.sh
    cd /workspace/scripts
    nohup python3 30_api_gateway.py >> /workspace/gateway_stats/gateway.log 2>&1 &
    echo "[$(date +%H:%M:%S)] WATCHDOG: Gateway restarted (PID $!)"
  fi
done
'

tmux send-keys -t vllm:watchdog "bash -c '$WATCHDOG_CMD'" Enter
log "✓ Watchdog running (checks every 30s)"

# ── 7. Summary ────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✓ Production stack is LIVE"
echo ""
echo "  Public URL : https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1"
echo ""
echo "  API Keys:"
echo "    Dev   : sk-qwen-dev-xK9mP2nL"
echo "    Prod  : sk-qwen-prod-rT5jW8vQ"
echo "    Spare : sk-qwen-spare-hN3cA6yD"
echo ""
echo "  tmux windows:"
echo "    tmux attach -t vllm:server   — vLLM inference (port 8001)"
echo "    tmux attach -t vllm:gateway  — API gateway (port 8000)"
echo "    tmux attach -t vllm:watchdog — auto-restart watchdog"
echo ""
echo "  Health : curl https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/health"
echo "  Usage  : curl https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1/usage \\"
echo "             -H 'Authorization: Bearer sk-qwen-prod-rT5jW8vQ'"
echo "══════════════════════════════════════════════════════════════"
