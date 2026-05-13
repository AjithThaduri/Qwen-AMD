# Troubleshooting Guide

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
