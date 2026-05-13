# Qwen3.6-35B-A3B on AMD MI300X — Phase 1 vLLM Deployment

Serving and benchmarking **Qwen/Qwen3.6-35B-A3B** on a **RunPod AMD Instinct MI300X OAM** (192 GiB VRAM) using **vLLM** with an OpenAI-compatible API.

Phase-1 goal: find the best quantization (Q4 GGUF → Q5 GGUF → FP8) for production by measuring real numbers, not assumptions. Q4 is tested first because it already gives proven quality in Ollama; FP8/BF16 are fallbacks if Q4 proves unstable or too slow on ROCm vLLM.

---

## Architecture

```
Your Mac (OpenAI SDK / curl)
         ↓ HTTPS
RunPod proxy: https://mv4dfc2mn9l8zc-8000.proxy.runpod.net
         ↓
vLLM OpenAI-compatible server  (port 8000)
         ↓
Qwen3-30B-A3B  on  MI300X (192 GiB VRAM)
```

---

## Quick start

### Step 0 — On your Mac: check local requirements

```bash
bash scripts/00_check_local_requirements.sh
```

Installs: `pip3 install openai`

### Step 1 — Read connection guide

```
scripts/01_connect_runpod_notes.md
```

Find your SSH command in RunPod → your pod → Connect → "SSH over exposed TCP".  
Set `RUNPOD_SSH_COMMAND` in your `.env`.

### Step 2 — SSH into the pod

```bash
# Copy your SSH command from RunPod and run it:
ssh root@YOUR_IP -p YOUR_PORT -i ~/.ssh/id_ed25519
```

### Step 3 — Copy the repo to the pod

```bash
# On the pod:
cd /workspace
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git repo
cd repo
cp .env.example .env
nano .env     # fill in HF_TOKEN; verify paths
```

### Step 4 — Check GPU

```bash
bash scripts/02_check_gpu.sh
```

### Step 5 — Install base packages

```bash
bash scripts/03_install_base.sh
```

### Step 6 — Install vLLM with ROCm support

```bash
bash scripts/04_install_vllm_rocm.sh
```

This takes 5–10 minutes. Installs PyTorch ROCm + vLLM.

### Step 7 — Download models

```bash
bash scripts/05_download_models.sh
```

Downloads:
- `Qwen3-30B-A3B-Q4_K_M.gguf` — ~18.6 GB
- `Qwen3-30B-A3B-Q5_K_M.gguf` — ~21.7 GB

Requires `HF_TOKEN` in `.env`.

### Step 8 — Start vLLM (inside tmux)

```bash
# Create a tmux session so vLLM keeps running after you disconnect:
tmux new -s vllm

# Start with Q4, 8K context first:
bash scripts/06_serve_q4_8k.sh

# Wait for: "Application startup complete."
# Detach with Ctrl+B then D
```

### Step 9 — Test from your Mac

```bash
# From your Mac:
bash scripts/12_test_models_endpoint.sh
python3 scripts/13_test_chat_non_stream.py
python3 scripts/14_test_chat_stream.py
```

### Step 10 — Benchmark

```bash
# From your Mac — full sweep at all concurrency levels:
python3 scripts/15_benchmark_concurrency.py \
    --base-url https://mv4dfc2mn9l8zc-8000.proxy.runpod.net \
    --api-key dev-test-key \
    --model qwen3-30b-a3b-q4 \
    --concurrency 1 5 10 25 50 \
    --requests 50 \
    --output results/benchmark_q4_8k.jsonl
```

### Step 11 — Monitor GPU during benchmark

On the pod (second tmux pane or SSH window):
```bash
bash scripts/16_watch_gpu.sh
```

Or collect to a file for later analysis:
```bash
bash scripts/17_collect_gpu_metrics.sh results/gpu_q4_8k.log 5
```

### Step 12 — Stop vLLM between runs

```bash
bash scripts/18_stop_vllm.sh
```

---

## Serving configurations

| Script | Quantization | Context | Use case |
|---|---|---|---|
| `06_serve_q4_8k.sh` | Q4_K_M GGUF | 8K | **Start here** |
| `07_serve_q4_16k.sh` | Q4_K_M GGUF | 16K | After Q4 8K passes |
| `08_serve_q5_8k.sh` | Q5_K_M GGUF | 8K | If Q4 quality isn't enough |
| `09_serve_q5_16k.sh` | Q5_K_M GGUF | 16K | Q5 + longer context |
| `10_serve_fp8_8k.sh` | FP8 (HF) | 8K | If GGUF is unstable |
| `11_serve_fp8_16k.sh` | FP8 (HF) | 16K | FP8 + longer context |

---

## Environment variables

Copy `.env.example` to `.env` and fill in:

| Variable | Description |
|---|---|
| `RUNPOD_SSH_COMMAND` | Full SSH command from RunPod |
| `RUNPOD_POD_ID` | Your pod ID (`mv4dfc2mn9l8zc`) |
| `RUNPOD_PUBLIC_BASE_URL` | `https://mv4dfc2mn9l8zc-8000.proxy.runpod.net` |
| `VLLM_API_KEY` | API key for vLLM (`dev-test-key` for testing) |
| `HF_TOKEN` | Hugging Face read token (for model download) |
| `MODEL_DIR` | Model storage path on pod (`/workspace/models`) |
| `Q4_MODEL_PATH` | Full path to Q4 GGUF on pod |
| `Q5_MODEL_PATH` | Full path to Q5 GGUF on pod |
| `FP8_MODEL_ID` | HF repo ID for FP8 model |
| `TOKENIZER_ID` | HF tokenizer for GGUF (`Qwen/Qwen3-30B-A3B`) |
| `GPU_MEMORY_UTILIZATION` | VRAM fraction for KV cache (`0.88`) |

---

## Repo structure

```
qwen-amd-vllm/
  .env.example           — copy to .env; never commit .env
  .gitignore
  README.md
  scripts/
    00_check_local_requirements.sh  — Mac: verify tools
    01_connect_runpod_notes.md      — SSH setup instructions
    02_check_gpu.sh                 — Pod: verify ROCm + GPU
    03_install_base.sh              — Pod: system packages
    04_install_vllm_rocm.sh         — Pod: vLLM + ROCm
    05_download_models.sh           — Pod: download GGUFs
    06–11_serve_*.sh                — Pod: start vLLM per config
    12_test_models_endpoint.sh      — Mac: GET /v1/models
    13_test_chat_non_stream.py      — Mac: non-streaming chat
    14_test_chat_stream.py          — Mac: streaming chat + TTFT
    15_benchmark_concurrency.py     — Mac: full benchmark
    16_watch_gpu.sh                 — Pod: live GPU monitor
    17_collect_gpu_metrics.sh       — Pod: log GPU metrics to file
    18_stop_vllm.sh                 — Pod: stop vLLM cleanly
  configs/
    q4_8k.env, q4_16k.env          — per-profile env overrides
    q5_8k.env, q5_16k.env
    fp8_8k.env, fp8_16k.env
  results/
    *.jsonl                         — raw benchmark results
    *.summary.json                  — per-run summaries
    *.log                           — GPU metric logs
  docs/
    runpod_setup.md                 — SSH, ports, tmux
    model_strategy.md               — why Q4→Q5→FP8 order
    benchmark_plan.md               — prompt set + thresholds
    experiment_log.md               — record every run
    troubleshooting.md              — common errors + fixes
```

---

## Model sources

| Format | Source | Est. size | Priority |
|---|---|---|---|
| Q4_K_M GGUF | `bartowski/Qwen_Qwen3.6-35B-A3B-GGUF` | ~21–23 GB | **Test first** |
| Q5_K_M GGUF | `bartowski/Qwen_Qwen3.6-35B-A3B-GGUF` | ~25–27 GB | Test second |
| FP8 (HF) | `Qwen/Qwen3.6-35B-A3B-FP8` | ~35–40 GB | Fallback if GGUF fails |
| Tokenizer | `Qwen/Qwen3.6-35B-A3B` | ~2 MB | Required for GGUF |

> No official Qwen GGUF exists for Qwen3.6-35B-A3B. Bartowski is the most
> reliable community source for vLLM GGUF compatibility (standard K-quant format).
> **Before downloading**, verify exact filenames at the repo link above.

---

## Safety notes

- **Never commit `.env`** — it contains your HF token and API key.
- `.gitignore` excludes `.env`, `*.gguf`, `*.safetensors`, `results/*.jsonl`.
- `VLLM_API_KEY` in `.env.example` is `dev-test-key` — change it for any non-local use.
- RunPod proxy URL is public; protect it with a strong API key in production.

---

## Docs

- [RunPod setup guide](docs/runpod_setup.md)
- [Model strategy](docs/model_strategy.md)
- [Benchmark plan](docs/benchmark_plan.md)
- [Experiment log](docs/experiment_log.md)
- [Troubleshooting](docs/troubleshooting.md)
