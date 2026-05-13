# 01 — Connecting to your RunPod pod

## Step 1: Find your SSH command in RunPod

1. Open https://www.runpod.io/console/pods
2. Click on your pod (the one with the AMD MI300X)
3. Click the **Connect** button
4. Look for the section labelled **"SSH over exposed TCP"**
5. Copy the full command — it will look like one of these:

   ```
   ssh root@213.173.99.12 -p 12345 -i ~/.ssh/id_ed25519
   ```
   or the newer RunPod SSH key format.

6. Paste that command into your `.env` file as `RUNPOD_SSH_COMMAND=`

> **Note:** If you see a token string instead of a full `ssh` command, you may
> need to add your public SSH key to RunPod first.  Go to
> RunPod → Settings → SSH Public Keys and paste the output of:
> ```
> cat ~/.ssh/id_ed25519.pub
> ```
> If you don't have an SSH key pair yet, generate one with:
> ```
> ssh-keygen -t ed25519 -C "runpod"
> ```

---

## Step 2: Test the connection from your Mac

Once you have the SSH command:

```bash
# Replace with your actual command from .env
ssh root@YOUR_IP -p YOUR_PORT -i ~/.ssh/id_ed25519
```

You should land at a root shell on the pod, showing something like:
```
root@pod-mv4dfc2mn9l8zc:~#
```

---

## Step 3: Confirm port 8000 is exposed

1. In RunPod, open your pod settings.
2. Under **"Exposed ports"**, confirm port **8000** is listed (TCP).
3. If it is not there, click **Edit** → add port 8000 → save.
4. Your vLLM API will be reachable at:
   ```
   https://mv4dfc2mn9l8zc-8000.proxy.runpod.net
   ```

---

## Step 4: Install tmux on the pod (first time only)

tmux keeps your server running even after you close the SSH session.

```bash
# On the pod:
apt-get update && apt-get install -y tmux
```

---

## Step 5: Start a tmux session for vLLM

```bash
# On the pod — create a named session:
tmux new -s vllm

# Run your serve script inside tmux, e.g.:
bash /workspace/repo/scripts/06_serve_q4_8k.sh

# Detach without stopping vLLM (press these keys in order):
# Ctrl+B  then  D

# Reconnect to the session later:
tmux attach -t vllm

# List all sessions:
tmux ls

# Kill the session (stops vLLM):
tmux kill-session -t vllm
```

---

## Step 6: Quick API test from your Mac

After vLLM is running on the pod, test it from your Mac:

```bash
# Check that the server is alive:
curl https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/health

# List available models:
curl -H "Authorization: Bearer dev-test-key" \
     https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1/models | jq .
```

---

## Useful pod commands

```bash
# View live vLLM logs inside tmux:
tmux attach -t vllm

# Check GPU status:
rocm-smi

# Check disk space (model storage):
df -h /workspace

# Check VRAM use by process:
rocm-smi --showmeminfo vram
```
