# Troubleshooting Guide

---

## INCIDENT: Base environment polluted during setup (2026-05-13)

### What happened

During Phase-1 setup, multiple `pip install` attempts in the **global Python environment**
created a broken, conflicting state. This is the root cause of all subsequent failures.

**Timeline of damage:**
1. `pip install vllm` (latest, 0.20.2) → pulled `torch 2.11.0+cu130` (CUDA) over existing ROCm torch
2. Force-reinstall `torch 2.3.1+rocm5.7` to recover GPU
3. `pip install vllm==0.5.3` → installs, but no GGUF and no Qwen3 arch support
4. `pip install transformers==4.46.3` → downgrade attempt
5. `pip install torch 2.5.1+rocm6.2` → ROCm upgrade attempt
6. `pip install vllm>=0.6.0 --upgrade` → pulled `torch 2.5.1+rocm6.2` + `torchaudio 2.11.0` (CUDA mismatch)
7. Force-reinstall `torch 2.9.1+rocm6.3`
8. `pip install vllm==0.16.0` → works, but Qwen3.6 needs Qwen3_5MoeForConditionalGeneration (not in 0.16.0)
9. `pip install transformers --upgrade` → installs 5.8.1, conflicts with vllm 0.16.0 (`requires <5`)
10. `pip install transformers==4.57.6` → downgrade again
11. `pip install transformers==5.8.1` → upgrade again to recognize qwen3_5_moe

**Current broken state (as of 2026-05-13):**
```
torch:         2.9.1+rocm6.3  (GPU visible — this part works)
vllm:          NOT INSTALLED   (was 0.16.0, then removed during repeated attempts)
transformers:  4.57.6          (downgraded, may be incomplete)
amdsmi:        23.2.0.1        (installed for vLLM platform detection)
ROCm userspace:/opt/rocm-5.7.0 (system-level, not changed)
AMDGPU driver: 6.10.5
Docker:        NOT AVAILABLE in this pod
```

### Why the base environment approach failed

- RunPod pods run a pre-configured Docker container with a specific Python environment
- `pip install` into the global site-packages breaks other system tools that depend on those versions
- vLLM on PyPI is the **CUDA** build — it always wants `torch==2.x.y+cu*`
- **The ROCm build of vLLM is not on PyPI** — it lives at `https://wheels.vllm.ai/rocm/`
- Mixing PyPI vLLM with ROCm torch is the core mistake

### What the correct path looks like

**Official vLLM ROCm wheels** (from `https://wheels.vllm.ai/rocm/`):
```bash
# In a fresh virtual environment:
pip install vllm==0.20.0+rocm721 \
    --extra-index-url https://wheels.vllm.ai/rocm/0.20.0/rocm721
```

Requirements per official docs:
- Python 3.12
- ROCm 7.0 or higher (userspace)
- glibc >= 2.35
- **This pod has ROCm 5.7 userspace** — compatibility with ROCm 7.x wheels is UNKNOWN

**Official serve command for Qwen3.6-35B-A3B-FP8 on MI300X:**
```bash
VLLM_ROCM_USE_AITER=1 vllm serve Qwen/Qwen3.6-35B-A3B-FP8 \
    --max-model-len 262144 \
    --reasoning-parser qwen3 \
    --trust-remote-code
```

### Decision needed before next step

Docker is not available in this pod (`docker: command not found`).

Options ranked by risk:
1. **Fresh RunPod pod** — choose a template with ROCm 7.x already installed.
   Risk: none. Everything starts clean. This pod can stay running alongside.
2. **Virtual env + vLLM ROCm wheel on current pod** — create `python3.12 -m venv /workspace/venv`
   then install `vllm==0.20.0+rocm721`. Risk: unknown — may fail if ROCm 7.x libs not present.
3. **Install ROCm 7.x userspace on current pod via apt** — add AMD apt repo, install ROCm 7.
   Risk: high — could destabilize pod; no rollback.

**Recommended: Option 2 (venv) first, fall back to Option 1 if wheels fail.**
Ask before proceeding.

---

## SSH / Connection issues

### "Connection refused" or timeout when SSHing

1. Check RunPod dashboard — is the pod running? (green status)
2. Is the port shown in RunPod the same port in your SSH command?
3. Did you add your public SSH key to RunPod → Settings → SSH Public Keys?
4. Try re-generating your SSH key and re-adding it.

### "Permission denied (publickey)"

```bash
# Verify your key exists:
ls -la ~/.ssh/id_ed25519

# Add it to the agent:
ssh-add ~/.ssh/id_ed25519

# Retry with verbose output to diagnose:
ssh -v root@YOUR_IP -p YOUR_PORT -i ~/.ssh/id_ed25519
```

---

## vLLM launch issues

### "CUDA out of memory" or "HIP out of memory"

- Reduce `GPU_MEMORY_UTILIZATION` in `.env` (try 0.80 or 0.75)
- Reduce `MAX_MODEL_LEN` (try 4096 before 8192)
- Ensure no other process is holding VRAM: `rocm-smi --showmeminfo vram`
- Kill any zombie vLLM processes: `bash scripts/18_stop_vllm.sh`

### "GGUF file not found"

- Run `ls -lh /workspace/models/` on the pod
- Verify `Q4_MODEL_PATH` in `.env` exactly matches the actual filename
- Re-run `05_download_models.sh`

### vLLM starts but crashes immediately with a segfault

- GGUF support in vLLM requires a recent version (≥0.4.x). Check: `vllm --version`
- Try `--dtype bfloat16` instead of `float16` (ROCm 6.x sometimes prefers bf16)
- Check ROCm version compatibility: `cat /opt/rocm/.info/version`

### "ValueError: ... quantization ... not supported"

- Your vLLM version may not support GGUF on ROCm yet.
- Try the FP8 path instead (`10_serve_fp8_8k.sh`).
- Check vLLM GitHub issues for ROCm GGUF support status.

### "--reasoning-parser qwen3 not recognized"

- This flag was added in vLLM ≥0.6.x. Check: `vllm --version`
- If older, remove `--reasoning-parser qwen3` from the serve command.

### "--enable-prefix-caching causes error"

- Try removing it — this flag was stabilized in vLLM 0.5.x.
- Prefix caching is optional; removing it won't break inference.

---

## API / endpoint issues

### `curl /health` returns 000 or connection refused

- vLLM may still be loading the model (takes 1–5 min). Wait and retry.
- Check if vLLM started: `tmux attach -t vllm`
- Check if port 8000 is exposed in RunPod pod settings.

### 401 Unauthorized

- Your request is missing `Authorization: Bearer <key>` header.
- Or the key in the request doesn't match `VLLM_API_KEY` in `.env`.

### 404 on `/v1/chat/completions`

- Wrong base URL — check `RUNPOD_PUBLIC_BASE_URL` in `.env`.
- Ensure you're appending `/v1/chat/completions`, not just `/v1`.

### Model name not found in response

- The `model` field in your request must match `--served-model-name` exactly.
- Check: `curl -H "Authorization: Bearer <key>" <BASE_URL>/v1/models`

---

## Performance issues

### Very slow first request (cold start)

- Normal — vLLM loads the model into VRAM on first request (or at startup).
- The serving scripts load the model at start time. Wait for "Application startup complete" in logs.

### High latency at low concurrency

- Check if `VLLM_ROCM_USE_AITER=1` is set — this enables AMD kernel optimizations.
- Check GPU utilization during inference: `rocm-smi` — should be > 80%.
- If GPU util is low, the bottleneck may be tokenization or network (RunPod proxy).

### Requests timing out at high concurrency

- Normal for very high concurrency — vLLM queues requests.
- Reduce `--requests` in the benchmark or lower concurrency.
- Check if requests are failing vs just slow: look at the `failure_count` in summary JSON.

---

## Download issues

### HF download fails with 401

- Your `HF_TOKEN` in `.env` may be missing, expired, or wrong.
- Go to https://huggingface.co/settings/tokens — create a new read token.
- Paste it as `HF_TOKEN=hf_xxxxxx` in `.env`.

### Download is very slow

- RunPod pods have fast internet (typically 1–10 Gbps).
- 18.6 GB at 1 Gbps takes ~2.5 min; at 100 Mbps takes ~25 min.
- Run inside a tmux session so a disconnect doesn't abort it.

### Disk full

- Check: `df -h /workspace`
- `/workspace` on RunPod is persistent but limited.
- Delete any unnecessary model files: `rm /workspace/models/unused.gguf`
- Models can also be stored in `/tmp` (faster but not persistent across pod restarts).

---

## ROCm / GPU not detected

### `rocm-smi` not found

```bash
# Check if ROCm is installed at the default path:
ls /opt/rocm/bin/rocm-smi

# Add to PATH:
export PATH=$PATH:/opt/rocm/bin
echo 'export PATH=$PATH:/opt/rocm/bin' >> ~/.bashrc
```

### PyTorch `cuda.is_available()` returns False

```bash
# Verify ROCm version:
cat /opt/rocm/.info/version

# Reinstall PyTorch for your ROCm version:
pip3 install torch --index-url https://download.pytorch.org/whl/rocm6.2

# Check if GPU appears at HIP level:
/opt/rocm/bin/rocminfo | grep "Name:"
```
