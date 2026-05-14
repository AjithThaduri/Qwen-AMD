#!/bin/bash
# Full bootstrap for vLLM on AMD MI300X (RunPod)
# Run this once after a pod terminate+recreate.
# /workspace/models/awq must already be present.
# Takes ~15-20 min (mostly downloading).

set -e
LOG=/workspace/bootstrap.log
echo "[$(date)] === BOOTSTRAP START ===" | tee $LOG

# 1. System packages
echo "[$(date)] Installing system packages..." | tee -a $LOG
apt-get update -qq
apt-get install -y tmux cron libopenmpi-dev openmpi-bin 2>&1 | tail -5 | tee -a $LOG

# 2. ROCm 7.2.3 (runtime libs needed by torch-rocm721)
echo "[$(date)] Adding ROCm 7.2.3 repo..." | tee -a $LOG
mkdir -p /etc/apt/keyrings
wget -qO /tmp/rocm.gpg.key https://repo.radeon.com/rocm/rocm.gpg.key
gpg --dearmor < /tmp/rocm.gpg.key > /etc/apt/keyrings/rocm.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2.3 jammy main" > /etc/apt/sources.list.d/rocm72.list
echo -e "Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600" > /etc/apt/preferences.d/rocm-pin-600
apt-get update -qq
echo "[$(date)] Installing ROCm 7.2.3 runtime (~6 GB)..." | tee -a $LOG
apt-get install -y --no-install-recommends rocm-hip-runtime hipblas hipblaslt hipsparse hipsolver rocblas hiprtc rocprofiler-sdk 2>&1 | tail -5 | tee -a $LOG

# 3. Conda env + vLLM
echo "[$(date)] Creating vllm-rocm conda env (Python 3.12)..." | tee -a $LOG
source /opt/conda/etc/profile.d/conda.sh
conda create -n vllm-rocm python=3.12 -y 2>&1 | tail -3 | tee -a $LOG
conda activate vllm-rocm
echo "[$(date)] Installing vLLM 0.20.2+rocm721 (~300 MB)..." | tee -a $LOG
pip install vllm==0.20.2+rocm721 --extra-index-url https://wheels.vllm.ai/rocm 2>&1 | tail -5 | tee -a $LOG

# 4. Sanity check
echo "[$(date)] Sanity check..." | tee -a $LOG
source /workspace/vllm_rocm_env.sh
python -c "import torch; print('torch:', torch.__version__, '| GPU:', torch.cuda.is_available())" 2>&1 | tee -a $LOG
vllm --version 2>&1 | tee -a $LOG

# 5. Auto-start setup
echo "[$(date)] Configuring auto-start..." | tee -a $LOG
cat > /etc/rc.local << 'RCEOF'
#!/bin/bash
/workspace/start_vllm.sh &
exit 0
RCEOF
chmod +x /etc/rc.local
systemctl enable rc-local 2>/dev/null || true
service cron start 2>/dev/null || true
(crontab -l 2>/dev/null | grep -v 'start_vllm'; echo '@reboot sleep 30 && /workspace/start_vllm.sh') | crontab -

# .bashrc guard (only add if not already present)
if ! grep -q 'start_vllm' /root/.bashrc; then
cat >> /root/.bashrc << 'BASHEOF'

# Auto-start vLLM if not already running
if ! tmux has-session -t vllm 2>/dev/null; then
    echo '[autostart] vLLM not running — starting now...'
    /workspace/start_vllm.sh
    echo '[autostart] vLLM starting in tmux session "vllm". Run: tmux attach -t vllm'
fi
BASHEOF
fi

# 6. Start vLLM now
echo "[$(date)] Starting vLLM in tmux..." | tee -a $LOG
/workspace/start_vllm.sh

echo "[$(date)] === BOOTSTRAP COMPLETE ===" | tee -a $LOG
echo "vLLM is loading. Monitor with: tail -f /workspace/serve_awq.log" | tee -a $LOG
