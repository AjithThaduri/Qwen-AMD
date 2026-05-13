#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 18_stop_vllm.sh
# Run this ON THE RUNPOD POD to cleanly stop a running vLLM process.
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "══════════════════════════════════════════════"
echo "  Stopping vLLM server"
echo "══════════════════════════════════════════════"
echo ""

# ── Option 1: Kill via port 8000 ──────────────────────────────────────────
PORT="${VLLM_PORT:-8000}"

echo "→ Looking for process on port $PORT..."

if command -v lsof &>/dev/null; then
    PID=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
elif command -v fuser &>/dev/null; then
    PID=$(fuser "$PORT"/tcp 2>/dev/null || true)
else
    PID=""
fi

if [ -n "$PID" ]; then
    echo "  Found PID(s): $PID"
    echo "  Sending SIGTERM (graceful shutdown)..."
    kill -TERM $PID 2>/dev/null || true
    sleep 3

    # Check if process is still alive; if so, force kill
    if kill -0 $PID 2>/dev/null; then
        echo "  Process still running — sending SIGKILL..."
        kill -KILL $PID 2>/dev/null || true
    fi
    echo "  ✓  vLLM process stopped."
else
    echo "  No process found on port $PORT."
fi

echo ""

# ── Option 2: Kill tmux session if it exists ──────────────────────────────
if command -v tmux &>/dev/null && tmux has-session -t vllm 2>/dev/null; then
    echo "→ Killing tmux session 'vllm'..."
    tmux kill-session -t vllm
    echo "  ✓  tmux session 'vllm' killed."
fi

echo ""
echo "  VRAM will be freed once the process exits."
echo "  Check with: rocm-smi"
echo ""
