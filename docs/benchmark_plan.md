# Benchmark Plan

## Purpose

Run this set of prompts on each model configuration (Q4 8K, Q5 8K, FP8 8K)
to compare quality and latency on a consistent basis.

Record results in `docs/experiment_log.md`.

---

## Prompt set

### Short prompts (< 50 input tokens)

These test raw speed and basic quality.

```
1. "Say hello in one sentence."
2. "What is 2 to the power of 10?"
3. "Name three large language models released in 2024."
4. "What does REST stand for?"
5. "Write a one-line Python function that reverses a string."
```

### Medium prompts (~100–200 input tokens)

These test instruction following and coherent multi-sentence output.

```
6. "Explain the difference between a process and a thread in 3 sentences."
7. "What are the pros and cons of microservices architecture? Give 2 pros and 2 cons."
8. "Write a brief email subject line and opening sentence for a weekly engineering update."
9. "Summarize the key idea of the CAP theorem in 2 sentences."
10. "What is a transformer model? Explain it to someone who knows Python but not ML."
```

### Long output prompts (~300–500 expected output tokens)

These test sustained coherence and latency under load.

```
11. "Write a Python function that implements binary search with detailed comments."
12. "Explain step by step how HTTPS works when you type a URL in a browser."
13. "Write a short product spec for a REST API endpoint that creates a user account."
14. "What are the 5 most important things to know before deploying an LLM to production?"
```

### Reasoning prompts (tests thinking/chain-of-thought if enabled)

```
15. "A train leaves city A at 60 km/h. Another leaves city B at 90 km/h toward city A.
     The cities are 300 km apart. When and where do they meet? Show your working."
16. "I have a list of 1 million integers. I need to find duplicates quickly.
     What data structure should I use and why?"
17. "Explain the tradeoff between p95 latency and throughput in an LLM serving system."
```

### Business-specific prompts (placeholder — customize for your use case)

```
18. [REPLACE WITH YOUR ACTUAL TASK PROMPT #1]
19. [REPLACE WITH YOUR ACTUAL TASK PROMPT #2]
20. [REPLACE WITH YOUR ACTUAL TASK PROMPT #3]
```

---

## Quality evaluation notes

For each prompt, record:

| Column | What to note |
|---|---|
| Factually correct | Yes / No / Partial |
| Coherent / readable | Yes / No |
| Follows instructions | Yes / No |
| Hallucinations | None / Minor / Major |
| Reasoning visible | Yes / No / N/A |
| Better/Worse than Ollama Q4 | Better / Same / Worse |

---

## Concurrency levels to test

For each model config, run `15_benchmark_concurrency.py` at:

| Level | Scenario |
|---|---|
| 1 | Single user, baseline latency |
| 5 | Small team usage |
| 10 | Moderate concurrent load |
| 25 | Busy production API |
| 50 | Peak load stress test |

Record p50, p95, p99 latency and failure rate for each.

---

## What "acceptable" means (define before testing)

Fill these in before you start, so you're not rationalizing after:

| Metric | Acceptable threshold |
|---|---|
| p95 latency (8K context) | _______ seconds |
| p95 latency (16K context) | _______ seconds |
| Failure rate at 50 concurrency | < _______ % |
| TTFT | < _______ seconds |
| Output quality | Same or better than Ollama Q4 baseline |
