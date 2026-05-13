# Model Strategy — Qwen/Qwen3.6-35B-A3B on AMD MI300X

## Decision framework

The goal is to find the quantization that gives:
- **Acceptable output quality** for your specific use case
- **p95 latency under your SLA target** (e.g. <5s for chat, <10s for long-form)
- **Low failure rate** under realistic concurrency
- **Reasonable VRAM use** (leave headroom for future context growth)

We test in order from cheapest to most expensive (VRAM, load time, complexity).

---

## Why Q4_K_M first

1. **Proven quality baseline.** Your 23 GB Ollama Q4 already gives acceptable output. That's the floor.
2. **Smallest download (~21–23 GB).** Fast to get onto the pod, fast model load.
3. **VRAM is not the constraint.** The MI300X has 192 GiB. Q4 leaves ~165 GiB free for KV cache — enough for aggressive concurrency.
4. **If Q4 quality is sufficient AND p95 latency is acceptable → stop. No need to go further.**

> **Critical caveat:** vLLM's GGUF loader is a completely different code path from Ollama/llama.cpp.
> vLLM dequantizes GGUF weights to float16 on-the-fly at inference time.
> The throughput may be lower than Ollama on a per-user basis, but the KV cache and
> batching advantages can make it faster under concurrent load.
> **Measure before deciding. Don't assume.**
>
> GGUF on ROCm vLLM is officially "experimental." If the model loads and
> inference works without errors, proceed to benchmarking. If it crashes or
> produces garbage output, switch to the FP8 path.

---

## Why Q5_K_M second

1. **Higher quality ceiling.** Q5_K_M retains more weight precision than Q4_K_M.
2. **Still small (~21.7 GB).** Only ~3 GB more than Q4.
3. **If Q4 latency is good but quality is noticeably degraded** in your specific prompts → upgrade to Q5.
4. Compare Q4 vs Q5 on your actual business prompts, not just "say hello."

---

## Why FP8 is fallback, not default

1. **You have proven Q4 quality.** Don't abandon what works without evidence.
2. **GGUF on ROCm vLLM is experimental** — but experimental doesn't mean broken. Test first.
3. **FP8 is the "native" vLLM format** — uses fully optimized attention kernels, no GGUF translation overhead, higher throughput per dollar.
4. **Switch to FP8 if:** GGUF crashes, produces corrupt output, or p95 latency exceeds your SLA at target concurrency.
5. FP8 requires a live HF download (~35–40 GB) and your HF token.
6. Check if `Qwen/Qwen3.6-35B-A3B-FP8` exists before relying on it:
   `curl -s -o /dev/null -w "%{http_code}" https://huggingface.co/Qwen/Qwen3.6-35B-A3B-FP8`
   (200 = exists, 404 = not yet published)

---

## Why BF16 is avoided initially

1. The base BF16 model is ~60 GB.
2. On 192 GiB you have room, but the KV cache shrinks significantly.
3. Quality difference over FP8 is marginal for most tasks.
4. Only consider BF16 if FP8 shows visible quality degradation on reasoning tasks.

---

## Why 8K context comes before 16K

1. Larger context = larger KV cache = more VRAM per concurrent request.
2. At concurrency 50 with 16K context, VRAM pressure multiplies fast.
3. Test 8K first to establish baseline latency and concurrency limits.
4. Then extend to 16K only if your actual use case needs long context.

---

## Why benchmark 50 concurrent users

1. Real production traffic is bursty.
2. A model that works at concurrency 1 can collapse at concurrency 10.
3. MI300X MoE models have non-linear scaling — KV cache contention matters.
4. You need p95 latency at 50 concurrent users, not just average at 1.

---

## Decision tree after benchmarking

```
Q4_K_M 8K benchmark
    ├── Quality acceptable AND p95 < target latency?
    │       └── YES → Use Q4_K_M 8K for production. DONE.
    │
    ├── Quality acceptable BUT p95 too high?
    │       └── Check: is it VRAM-bound or compute-bound?
    │           → Reduce concurrency, or reduce max_tokens, or increase GPU util
    │
    ├── Quality not acceptable?
    │       └── Test Q5_K_M 8K
    │               ├── Quality acceptable? → Use Q5
    │               └── Still not acceptable? → Test FP8
    │
    └── GGUF crashes or throws errors?
            └── Switch to FP8 directly (10_serve_fp8_8k.sh)
```

---

## How to measure quality

Don't rely on "feels good." Use repeatable prompts (see `benchmark_plan.md`):

1. Run the exact same prompts on Q4, Q5, and FP8.
2. Record outputs in `docs/experiment_log.md`.
3. Note any factual errors, hallucinations, or broken reasoning.
4. If results are identical → Q4 wins on cost.
