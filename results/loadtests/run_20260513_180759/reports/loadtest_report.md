# Qwen MI300X vLLM Load Test Report

**Generated:** 2026-05-13 12:45:42 UTC

## Target environment

- **API base URL:** `https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1`
- **Model:** `qwen3.6-35b-a3b-awq`
- **Backend:** vLLM on AMD MI300X (RunPod); max_model_len 8192 on server.
- **Client:** macOS load generator (this repo). Authentication used the shared development key `dev-test-key` for this test run only.

## Environment assumptions

- Network path includes RunPod HTTP proxy; latencies include WAN effects.
- Output token counts are approximated as `output_chars // 4` per request.
- Non-streaming summaries set TTFT equal to total latency by convention (see per-summary `ttft_note`).
- Per-request timeout was enforced by the benchmark client; failed requests are counted but do not stop the matrix.

## Summary table (all tests)

| label | stream | concurrency | requests | max_tokens | success_count | failure_count | failure_rate | approx_output_tokens_per_sec | latency_avg_sec | latency_p95_sec | latency_p99_sec | ttft_avg_sec | ttft_p95_sec |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01_smoke_short_stream | True | 1 | 1 | 100 | 1 | 0 | 0.0 | 65.5853 | 1.371722 | 1.371722 | 1.371722 | 0.543414 | 0.543414 |
| T02_smoke_medium_stream | True | 1 | 3 | 256 | 3 | 0 | 0.0 | 95.369 | 2.988156 | 3.26504 | 3.27237 | 0.811027 | 1.094359 |
| T03_medium_c5_r20_s256 | True | 5 | 20 | 256 | 20 | 0 | 0.0 | 258.547 | 5.514536 | 6.014352 | 6.019918 | 0.522141 | 0.860081 |
| T04_medium_c10_r30_s256 | True | 10 | 30 | 256 | 30 | 0 | 0.0 | 431.1003 | 6.551552 | 7.095715 | 7.104616 | 0.531089 | 0.844813 |
| T05_medium_c20_r40_s256 | True | 20 | 40 | 256 | 40 | 0 | 0.0 | 964.1709 | 5.715226 | 5.926386 | 5.974847 | 0.783384 | 0.970846 |
| T06_medium_c50_r50_s256 | True | 50 | 50 | 256 | 50 | 0 | 0.0 | 2276.734 | 6.067787 | 6.140549 | 6.164942 | 0.96924 | 1.080439 |
| T07_large_c10_r20_s512 | True | 10 | 20 | 512 | 20 | 0 | 0.0 | 437.548 | 12.216923 | 12.360556 | 12.451753 | 0.591695 | 0.672417 |
| T08_large_c20_r20_s512 | True | 20 | 20 | 512 | 20 | 0 | 0.0 | 1110.7964 | 9.341763 | 9.465668 | 9.491234 | 0.552723 | 0.673911 |
| T09_large_c50_r50_s512 | True | 50 | 50 | 512 | 50 | 0 | 0.0 | 2545.5825 | 10.208546 | 10.378091 | 10.442894 | 0.806362 | 0.997664 |
| T10_reasoning_c10_r20_s768 | True | 10 | 20 | 768 | 20 | 0 | 0.0 | 293.6467 | 20.714539 | 20.942914 | 21.01728 | 0.574662 | 0.621538 |
| T11_reasoning_c20_r20_s768 | True | 20 | 20 | 768 | 20 | 0 | 0.0 | 759.9319 | 16.022479 | 16.035156 | 16.136055 | 0.537616 | 0.55256 |
| T12_coding_c5_r10_s1024 | True | 5 | 10 | 1024 | 10 | 0 | 0.0 | 230.9908 | 21.963584 | 22.176396 | 22.21039 | 0.609896 | 0.669987 |
| T13_coding_c10_r20_s1024 | True | 10 | 20 | 1024 | 20 | 0 | 0.0 | 386.4412 | 26.308136 | 26.545956 | 26.644207 | 0.593074 | 0.610209 |
| T14_medium_c10_r20_s256_nostream | False | 10 | 20 | 256 | 20 | 0 | 0.0 | 439.4889 | 6.468594 | 6.502222 | 6.567998 | 6.468594 | 6.502222 |
| T15_large_c10_r20_s512_nostream | False | 10 | 20 | 512 | 20 | 0 | 0.0 | 436.9451 | 12.198958 | 12.30147 | 12.304567 | 12.198958 | 12.30147 |

## Highlights

- **Best throughput (approx output tok/s, wall clock):** `T09_large_c50_r50_s512` (throughput 2545.5825 tok/s)
- **Best average end-to-end latency:** `T01_smoke_short_stream` (avg latency 1.371722 s)
- **Worst p95 latency:** `T13_coding_c10_r20_s1024` (p95 26.545956 s)

## Streaming vs non-streaming

### Streaming (`stream: true`)
| label | stream | concurrency | requests | max_tokens | success_count | failure_count | failure_rate | approx_output_tokens_per_sec | latency_avg_sec | latency_p95_sec | latency_p99_sec | ttft_avg_sec | ttft_p95_sec |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T01_smoke_short_stream | True | 1 | 1 | 100 | 1 | 0 | 0.0 | 65.5853 | 1.371722 | 1.371722 | 1.371722 | 0.543414 | 0.543414 |
| T02_smoke_medium_stream | True | 1 | 3 | 256 | 3 | 0 | 0.0 | 95.369 | 2.988156 | 3.26504 | 3.27237 | 0.811027 | 1.094359 |
| T03_medium_c5_r20_s256 | True | 5 | 20 | 256 | 20 | 0 | 0.0 | 258.547 | 5.514536 | 6.014352 | 6.019918 | 0.522141 | 0.860081 |
| T04_medium_c10_r30_s256 | True | 10 | 30 | 256 | 30 | 0 | 0.0 | 431.1003 | 6.551552 | 7.095715 | 7.104616 | 0.531089 | 0.844813 |
| T05_medium_c20_r40_s256 | True | 20 | 40 | 256 | 40 | 0 | 0.0 | 964.1709 | 5.715226 | 5.926386 | 5.974847 | 0.783384 | 0.970846 |
| T06_medium_c50_r50_s256 | True | 50 | 50 | 256 | 50 | 0 | 0.0 | 2276.734 | 6.067787 | 6.140549 | 6.164942 | 0.96924 | 1.080439 |
| T07_large_c10_r20_s512 | True | 10 | 20 | 512 | 20 | 0 | 0.0 | 437.548 | 12.216923 | 12.360556 | 12.451753 | 0.591695 | 0.672417 |
| T08_large_c20_r20_s512 | True | 20 | 20 | 512 | 20 | 0 | 0.0 | 1110.7964 | 9.341763 | 9.465668 | 9.491234 | 0.552723 | 0.673911 |
| T09_large_c50_r50_s512 | True | 50 | 50 | 512 | 50 | 0 | 0.0 | 2545.5825 | 10.208546 | 10.378091 | 10.442894 | 0.806362 | 0.997664 |
| T10_reasoning_c10_r20_s768 | True | 10 | 20 | 768 | 20 | 0 | 0.0 | 293.6467 | 20.714539 | 20.942914 | 21.01728 | 0.574662 | 0.621538 |
| T11_reasoning_c20_r20_s768 | True | 20 | 20 | 768 | 20 | 0 | 0.0 | 759.9319 | 16.022479 | 16.035156 | 16.136055 | 0.537616 | 0.55256 |
| T12_coding_c5_r10_s1024 | True | 5 | 10 | 1024 | 10 | 0 | 0.0 | 230.9908 | 21.963584 | 22.176396 | 22.21039 | 0.609896 | 0.669987 |
| T13_coding_c10_r20_s1024 | True | 10 | 20 | 1024 | 20 | 0 | 0.0 | 386.4412 | 26.308136 | 26.545956 | 26.644207 | 0.593074 | 0.610209 |

### Non-streaming (`stream: false`)
| label | stream | concurrency | requests | max_tokens | success_count | failure_count | failure_rate | approx_output_tokens_per_sec | latency_avg_sec | latency_p95_sec | latency_p99_sec | ttft_avg_sec | ttft_p95_sec |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T14_medium_c10_r20_s256_nostream | False | 10 | 20 | 256 | 20 | 0 | 0.0 | 439.4889 | 6.468594 | 6.502222 | 6.567998 | 6.468594 | 6.502222 |
| T15_large_c10_r20_s512_nostream | False | 10 | 20 | 512 | 20 | 0 | 0.0 | 436.9451 | 12.198958 | 12.30147 | 12.304567 | 12.198958 | 12.30147 |

## Failure analysis

No test exceeded a 20% failure rate.

## Recommended production limits

- Treat **p95/p99 latency** and **failure_rate** under sustained concurrency as primary SLO drivers.
- Prefer **streaming** for user-perceived latency when TTFT matters; compare decode throughput separately.
- Cap **max_tokens** and concurrent streams per user to keep KV footprint predictable on a single MI300X.

## Recommendation for ~50 concurrent users

- From the matrix row closest to 50 concurrent clients, compare throughput vs p95 latency.
- If p95 latency or failures rise sharply near 50, queue or autoscale before adding users on one GPU.
- Monitor **prefill vs decode** on the server (e.g. `rocm-smi` during load); client TTFT spikes often track prefill contention.

## Notes (TTFT, p95/p99, throughput, failures)

- **TTFT:** streaming TTFT is first non-empty token; non-streaming TTFT matches full response time in this harness.
- **p95/p99:** computed with linear interpolation on successful requests.
- **Throughput:** `approx_output_tokens_per_sec` divides total successful output tokens by total wall time for the batch.
- **Failure rate:** failures include timeouts and HTTP/API errors; inspect `errors_top_5` per test in summary JSON.

## Raw artifacts

- Raw JSONL: `/Users/ajiththaduri/Desktop/Qwen-AMD-Optimised/results/loadtests/run_20260513_180759/raw`
- Summary JSON: `/Users/ajiththaduri/Desktop/Qwen-AMD-Optimised/results/loadtests/run_20260513_180759/summaries`
