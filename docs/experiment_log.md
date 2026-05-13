# Experiment Log

Record every benchmark run here. One row per experiment.

---

## Log table

| ID | Date | GPU | Format | Model path / ID | max_model_len | gpu_mem_util | quant | concurrency | avg_input_tokens | max_output_tokens | p50_latency_s | p95_latency_s | p99_latency_s | avg_ttft_s | VRAM_used_GB | GPU_util_pct | failure_rate_pct | decision | notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| EXP-001 | | MI300X | gguf | Q4_K_M 8K | 8192 | 0.88 | Q4_K_M | 1 | | 200 | | | | | | | | | |
| EXP-002 | | MI300X | gguf | Q4_K_M 8K | 8192 | 0.88 | Q4_K_M | 5 | | 200 | | | | | | | | | |
| EXP-003 | | MI300X | gguf | Q4_K_M 8K | 8192 | 0.88 | Q4_K_M | 10 | | 200 | | | | | | | | | |
| EXP-004 | | MI300X | gguf | Q4_K_M 8K | 8192 | 0.88 | Q4_K_M | 25 | | 200 | | | | | | | | | |
| EXP-005 | | MI300X | gguf | Q4_K_M 8K | 8192 | 0.88 | Q4_K_M | 50 | | 200 | | | | | | | | | |
| EXP-006 | | MI300X | gguf | Q5_K_M 8K | 8192 | 0.88 | Q5_K_M | 1 | | 200 | | | | | | | | | |
| EXP-007 | | MI300X | gguf | Q5_K_M 8K | 8192 | 0.88 | Q5_K_M | 10 | | 200 | | | | | | | | | |
| EXP-008 | | MI300X | gguf | Q5_K_M 8K | 8192 | 0.88 | Q5_K_M | 50 | | 200 | | | | | | | | | |
| EXP-009 | | MI300X | fp8_hf | FP8 8K | 8192 | 0.88 | FP8 | 1 | | 200 | | | | | | | | | |
| EXP-010 | | MI300X | fp8_hf | FP8 8K | 8192 | 0.88 | FP8 | 10 | | 200 | | | | | | | | | |
| EXP-011 | | MI300X | fp8_hf | FP8 8K | 8192 | 0.88 | FP8 | 50 | | 200 | | | | | | | | | |
| EXP-012 | | MI300X | gguf | Q4_K_M 16K | 16384 | 0.88 | Q4_K_M | 10 | | 400 | | | | | | | | | |

---

## Notes template (copy for each experiment)

```
## EXP-XXX — <short description>

**Date:** YYYY-MM-DD
**Config:** <script name>
**Model:** <path or HF ID>
**Context:** <8192 or 16384>
**Concurrency:** <level>

### What was tested
<describe>

### GPU stats during run
- VRAM used: __ GB / 192 GB
- GPU utilization: ___%
- Power draw: ___ W
- Temperature: ___°C

### Results
- p50 latency: __s
- p95 latency: __s
- p99 latency: __s
- TTFT avg:    __s
- Failure rate: __%
- Requests/sec: __

### Quality notes
<notes on output quality vs Ollama Q4 baseline>

### Decision
- [ ] Move to next experiment
- [ ] Use this config for production
- [ ] Need to investigate issue: <describe>
```

---

## Final recommendation (fill in after all experiments)

| Chosen config | |
|---|---|
| Format | |
| Model path / ID | |
| Context window | |
| Concurrency limit | |
| Reason | |
| Confirmed date | |
