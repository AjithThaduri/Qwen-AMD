# RunPod Setup Guide

## Your pod details

| Property | Value |
|---|---|
| Pod ID | `mv4dfc2mn9l8zc` |
| GPU | AMD Instinct MI300X OAM |
| VRAM | 192 GiB |
| RAM | ~263 GiB |
| OS | Ubuntu 22.04.4 LTS |
| SSH (direct TCP) | `ssh root@213.173.96.55 -p 14871 -i ~/.ssh/id_ed25519` |
| SSH (RunPod proxy) | `ssh mv4dfc2mn9l8zc-644116fc@ssh.runpod.io -i ~/.ssh/id_ed25519` |
| vLLM public URL | `https://mv4dfc2mn9l8zc-8000.proxy.runpod.net` |

---

## 1. Find your SSH command

1. Go to https://www.runpod.io/console/pods
2. Click your pod
3. Click **Connect**
4. Look for **"SSH over exposed TCP"** — copy the full command starting with `ssh`

It should look like:
```
ssh root@213.173.99.12 -p 12345 -i ~/.ssh/id_ed25519
```

> **If you only see a token string and not a full SSH command:**
> You need to add your public SSH key to RunPod first.
> 1. On your Mac, run: `cat ~/.ssh/id_ed25519.pub`
>    (If the file doesn't exist, run: `ssh-keygen -t ed25519 -C "runpod"`)
> 2. In RunPod → top-right menu → **Settings** → **SSH Public Keys**
> 3. Paste your public key and save
> 4. Restart the pod or reconnect

---

## 2. Connect from your Mac

```bash
# Paste your SSH command here:
ssh root@YOUR_IP -p YOUR_PORT -i ~/.ssh/id_ed25519

# You should see:
# root@pod-mv4dfc2mn9l8zc:~#
```

---

## 3. Confirm port 8000 is exposed

1. In RunPod, open your pod → click **Edit**
2. Under **"Expose HTTP Ports"** or **"TCP Port Mappings"**, add `8000`
3. Save and restart if needed

Your vLLM API will then be accessible at:
```
https://mv4dfc2mn9l8zc-8000.proxy.runpod.net
```

Test it from your Mac:
```bash
curl https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/health
```

---

## 4. Copy the repo to the pod

Option A — git clone (recommended):
```bash
# On the pod:
cd /workspace
git clone https://github.com/YOUR_USERNAME/YOUR_REPO_NAME.git repo
cd repo
cp .env.example .env
nano .env   # fill in HF_TOKEN and verify paths
```

Option B — rsync from Mac:
```bash
# On your Mac:
rsync -avz --exclude '.git' --exclude '.env' \
    /path/to/local/repo/ \
    root@YOUR_IP:/workspace/repo/ \
    -e "ssh -p YOUR_PORT -i ~/.ssh/id_ed25519"
```

---

## 5. Set up tmux on the pod

tmux keeps vLLM running even after you close your SSH session.

```bash
# Install (first time only):
apt-get install -y tmux

# Create a session named 'vllm':
tmux new -s vllm

# Start vLLM inside the session:
bash /workspace/repo/scripts/06_serve_q4_8k.sh

# Detach without stopping vLLM:
# Press Ctrl+B, release, then press D

# Later, reconnect:
tmux attach -t vllm

# List all sessions:
tmux ls

# Kill a session (stops vLLM):
tmux kill-session -t vllm
```

---

## 6. Suggested multi-pane layout

Open **three** SSH connections or tmux panes:

| Pane | Purpose |
|---|---|
| Pane 1 | vLLM server (tmux session `vllm`) |
| Pane 2 | GPU monitor: `bash scripts/16_watch_gpu.sh` |
| Pane 3 | Benchmark runner + general commands |

```bash
# Split tmux panes (inside a tmux session):
Ctrl+B %     # split vertical
Ctrl+B "     # split horizontal
Ctrl+B →/←  # move between panes
```

---

## 7. Useful one-liners on the pod

```bash
# Check GPU VRAM usage:
rocm-smi --showmeminfo vram

# Check all GPU stats:
rocm-smi

# See what's listening on port 8000:
lsof -i :8000

# Check disk space:
df -h /workspace

# Tail vLLM logs (if running in tmux):
tmux attach -t vllm

# Kill vLLM cleanly:
bash /workspace/repo/scripts/18_stop_vllm.sh
```

---

## 8. How RunPod proxy URLs work

RunPod automatically creates a public HTTPS URL for any exposed port:
```
https://<POD_ID>-<PORT>.proxy.runpod.net
```

For your pod and port 8000:
```
https://mv4dfc2mn9l8zc-8000.proxy.runpod.net
```

All requests go through RunPod's reverse proxy over HTTPS.  
Your vLLM server only needs to listen on `0.0.0.0:8000` (plain HTTP internally).
