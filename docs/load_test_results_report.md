# Load test results report — Qwen3.6-35B-A3B AWQ on vLLM (MI300X)

**Run directory:** `results/loadtests/run_20260513_180759`  
**Machine-generated tables:** `run_20260513_180759/reports/loadtest_report.md` and `run_20260513_180759/reports/loadtest_summary.csv`  
**Client:** macOS, `scripts/benchmark_openai_load.py` + `scripts/run_loadtest_matrix.sh`  
**Endpoint:** OpenAI-compatible base URL ending in `/v1` on RunPod (see auto-generated report for exact URL).  
**Auth:** `dev-test-key` used only for this benchmark (do not treat as production secret).

---

## 1. Executive summary

Fifteen client-side scenarios were executed against the live vLLM service: smoke tests, stepped concurrency on a medium prompt, heavy-output and reasoning-style prompts, long coding generations, and a non-streaming comparison. **Every request succeeded** (`failure_rate = 0` for all cases). Approximate output throughput (wall-clock, `chars // 4` per request) ranged from about **66 tok/s** on the smallest smoke case up to about **2546 tok/s** on the highest-throughput streaming case in this matrix.

---

## 2. What was measured

| Dimension | Notes |
| --- | --- |
| Latency | End-to-end time per request (streaming: full stream; non-streaming: full completion). |
| TTFT | Streaming: time to first non-empty token. Non-streaming: intentionally set equal to full latency in the harness (see per-summary `ttft_note`). |
| Throughput | `approx_output_tokens_per_sec` = total successful approximate output tokens ÷ batch wall time. |
| Failures | Timeouts and API errors recorded per request; matrix continues on partial failure. |

All figures include **network** latency to RunPod, not GPU-only time.

---

## 3. Results overview

### 3.1 Reliability

- **335 / 335** successful completions across the matrix (sum of `success_count` over all fifteen summaries).
- **No** scenario exceeded the 20% failure-rate alert threshold.

### 3.2 Throughput highlights (approximate output tok/s, wall clock)

| Rank | Test label | Scenario (short) | approx_output_tokens_per_sec |
| --- | --- | --- | ---: |
| 1 | `T09_large_c50_r50_s512` | Large prompt, 50 concurrent, 50 reqs, 512 cap | **2546** |
| 2 | `T06_medium_c50_r50_s256` | Medium prompt, 50 concurrent, 50 reqs, 256 cap | **2277** |
| 3 | `T05_medium_c20_r40_s256` | Medium, 20 concurrent, 40 reqs | **964** |

Heavy **decode** (long `max_tokens`, reasoning, coding) lowers aggregate tok/s because each request holds the model longer; that is expected, not a sign of broken serving.

### 3.3 Latency highlights (average request latency, seconds)

| Observation | Test | latency_avg_sec (approx.) |
| --- | --- | ---: |
| Lightest | `T01_smoke_short_stream` | **1.37** |
| Medium load reference | `T04_medium_c10_r30_s256` | **6.55** |
| Heaviest in matrix (long generations) | `T13_coding_c10_r20_s1024` | **26.31** |

**Tail latency:** Worst **p95** in this run was **`T13_coding_c10_r20_s1024`** at about **26.5 s** (20 requests, concurrency 10, `max_tokens` 1024, streaming).

---

## 4. Focused comparisons

### 4.1 “Fifty concurrent users” proxy (`T06`)

`T06_medium_c50_r50_s256` saturated **50** parallel streaming requests with **256** output cap each. In this run:

- **Throughput:** ~2277 approximate output tok/s (batch wall).
- **Average latency:** ~6.07 s; **p95** ~6.14 s; **p99** ~6.16 s.
- **TTFT (streaming):** average ~0.97 s; **p95** ~1.08 s.

Interpretation: for **short-to-medium** assistant-style answers at this cap, **50 concurrent streaming clients** remained **stable and fast-tailed** in this single snapshot. Workloads that routinely hit **768–1024** new tokens per call will need more headroom (see `T10`–`T13`).

### 4.2 Streaming vs non-streaming (same shape: 10 × 20 requests)

| Case | Stream | Prompt class | max_tokens | latency_avg_sec | approx_output_tokens_per_sec |
| --- | ---: | --- | ---: | ---: | ---: |
| `T04_medium_c10_r30_s256` | yes | medium | 256 | 6.55 | 431 |
| `T14_medium_c10_r20_s256_nostream` | no | medium | 256 | 6.47 | 439 |

| Case | Stream | Prompt class | max_tokens | latency_avg_sec | approx_output_tokens_per_sec |
| --- | ---: | --- | ---: | ---: | ---: |
| `T07_large_c10_r20_s512` | yes | large | 512 | 12.22 | 438 |
| `T15_large_c10_r20_s512_nostream` | no | large | 512 | 12.20 | 437 |

End-to-end **wall time and aggregate tok/s** were **similar** between stream and non-stream for these matched scenarios; the main product difference is **incremental delivery** (streaming TTFT ~0.5–0.8 s vs waiting for the full payload in one chunk).

---

## 5. Recommendations (from this run)

1. **SLOs:** Track **p95/p99 latency** and **error rate** under load; use this matrix as a baseline when you change model path, `max_model_len`, or quantization.
2. **50 SaaS-style users:** The **medium / 256-token** pattern at 50-way concurrency looked healthy here; for **long** generations or **code** at **1024** tokens, expect **much higher** tail latencies unless you queue, shard, or add capacity.
3. **Capacity planning:** When users run **large** prompts plus **high** `max_tokens`, treat **`T09`-class** throughput as an **optimistic** ceiling and **`T13`-class** latency as a **stress** anchor for worst-case UX.

---

## 6. Reproducibility

```bash
# Re-run full matrix (creates a new timestamped run_* directory)
bash scripts/run_loadtest_matrix.sh

# Regenerate Markdown + CSV for an existing run
.venv/bin/python3 scripts/generate_loadtest_report.py results/loadtests/run_20260513_180759
```

Raw per-request lines live under `run_*/raw/*.jsonl`; aggregated metrics under `run_*/summaries/*.json`.

---

## 7. Limitations

- Output token counts are **approximate** (`character_count // 4`), not tokenizer-accurate.
- Single run, single client host, single time window; no sustained soak beyond the scripted batches.
- Results are **not** a substitute for on-server metrics (`rocm-smi`, vLLM logs, queue depth).
