#!/bin/bash
# Auto-start script for vLLM on AMD MI300X (RunPod)
# Starts vLLM inside a persistent tmux session on pod boot.

LOG=/workspace/autostart_vllm.log
echo "[$(date)] autostart triggered" >> $LOG

# Already running? Do nothing.
if tmux has-session -t vllm 2>/dev/null; then
    echo "[$(date)] tmux session 'vllm' already exists — skipping" >> $LOG
    exit 0
fi

# Source the ROCm + conda environment
source /workspace/vllm_rocm_env.sh >> $LOG 2>&1

# Create tmux session and launch vLLM inside it
tmux new-session -d -s vllm -x 220 -y 50
tmux send-keys -t vllm \
    "source /workspace/vllm_rocm_env.sh && vllm serve /workspace/models/awq \
     --served-model-name qwen3.6-35b-a3b-awq \
     --host 0.0.0.0 --port 8000 \
     --max-model-len 8192 \
     --gpu-memory-utilization 0.85 \
     --trust-remote-code \
     --api-key dev-test-key \
     2>&1 | tee /workspace/serve_awq.log" Enter

echo "[$(date)] tmux session 'vllm' started" >> $LOG
