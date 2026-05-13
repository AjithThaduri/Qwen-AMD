#!/usr/bin/env python3
"""
15_benchmark_concurrency.py
Run from your MAC (or the pod) after vLLM is running.

Benchmarks the vLLM endpoint at multiple concurrency levels and saves
results as JSONL + summary JSON in the results/ directory.

Usage examples:
    # Quick single-level test:
    python3 scripts/15_benchmark_concurrency.py \\
        --base-url https://mv4dfc2mn9l8zc-8000.proxy.runpod.net \\
        --api-key dev-test-key \\
        --model qwen3-30b-a3b-q4 \\
        --concurrency 1 \\
        --requests 10

    # Full benchmark sweep (1, 5, 10, 25, 50):
    python3 scripts/15_benchmark_concurrency.py \\
        --base-url https://mv4dfc2mn9l8zc-8000.proxy.runpod.net \\
        --api-key dev-test-key \\
        --model qwen3-30b-a3b-q4 \\
        --concurrency 1 5 10 25 50 \\
        --requests 50 \\
        --output results/benchmark_q4_8k.jsonl

    # Load prompts from a file (one prompt per line):
    python3 scripts/15_benchmark_concurrency.py ... --prompt-file prompts.txt
"""

import argparse
import asyncio
import json
import os
import statistics
import sys
import time
from datetime import datetime
from pathlib import Path

# ── Load .env defaults ────────────────────────────────────────────────────
repo_root = Path(__file__).parent.parent
env_file = repo_root / ".env"
if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip().strip('"'))

# ── Argument parsing ──────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description="Benchmark vLLM concurrency")
parser.add_argument("--base-url",
    default=os.environ.get("RUNPOD_PUBLIC_BASE_URL", ""),
    help="vLLM base URL (without /v1)")
parser.add_argument("--api-key",
    default=os.environ.get("VLLM_API_KEY", "dev-test-key"))
parser.add_argument("--model",
    default=os.environ.get("SERVED_MODEL_NAME_Q4", "qwen3-30b-a3b-q4"),
    help="Model name as served by vLLM (--served-model-name)")
parser.add_argument("--concurrency", type=int, nargs="+",
    default=[1, 5, 10, 25, 50],
    help="Concurrency levels to test (space-separated, e.g. 1 5 10)")
parser.add_argument("--requests", type=int, default=50,
    help="Total requests per concurrency level")
parser.add_argument("--max-tokens", type=int, default=200,
    help="Max tokens to generate per request")
parser.add_argument("--prompt-file", type=str, default=None,
    help="Path to file with prompts (one per line). If not set, uses defaults.")
parser.add_argument("--output", type=str, default=None,
    help="Output JSONL file path. Defaults to results/benchmark_<model>_<ts>.jsonl")
parser.add_argument("--stream", action="store_true", default=True,
    help="Use streaming to measure TTFT (default: True)")
parser.add_argument("--no-stream", dest="stream", action="store_false",
    help="Disable streaming (no TTFT measurement)")
args = parser.parse_args()

# ── Validate ──────────────────────────────────────────────────────────────
if not args.base_url:
    print("✗ --base-url is required (or set RUNPOD_PUBLIC_BASE_URL in .env)")
    sys.exit(1)

# ── Import openai ─────────────────────────────────────────────────────────
try:
    from openai import AsyncOpenAI
except ImportError:
    print("✗ openai package not installed. Run: pip3 install openai")
    sys.exit(1)

# ── Default prompts ───────────────────────────────────────────────────────
DEFAULT_PROMPTS = [
    "Say hello in exactly one sentence.",
    "What is 15 multiplied by 37? Just give the number.",
    "Name three programming languages in a single line.",
    "What is the capital of France? One word answer.",
    "Explain recursion in one sentence.",
    "What does CPU stand for? Answer in one line.",
    "Write a haiku about coding.",
    "What is the purpose of a REST API? One sentence.",
    "Name two famous algorithms in computer science.",
    "What is 2 to the power of 10?",
]

def load_prompts(prompt_file):
    if prompt_file:
        p = Path(prompt_file)
        if not p.exists():
            print(f"✗ Prompt file not found: {prompt_file}")
            sys.exit(1)
        lines = [l.strip() for l in p.read_text().splitlines() if l.strip()]
        print(f"  ✓  Loaded {len(lines)} prompts from {prompt_file}")
        return lines
    return DEFAULT_PROMPTS

prompts = load_prompts(args.prompt_file)

# ── Output paths ──────────────────────────────────────────────────────────
ts = datetime.now().strftime("%Y%m%d_%H%M%S")
safe_model = args.model.replace("/", "_").replace(":", "_")

if args.output:
    output_jsonl = Path(args.output)
else:
    output_jsonl = repo_root / "results" / f"benchmark_{safe_model}_{ts}.jsonl"

output_summary = output_jsonl.with_suffix(".summary.json")
output_jsonl.parent.mkdir(parents=True, exist_ok=True)

# ── Async request runner ──────────────────────────────────────────────────
async def run_request(client, model, prompt, max_tokens, use_stream, request_id):
    """Run a single request and return timing + result metrics."""
    start = time.time()
    first_token_time = None
    output_tokens = 0
    success = True
    error = None

    try:
        if use_stream:
            got_first = False
            async with client.chat.completions.stream(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=max_tokens,
            ) as stream:
                async for event in stream:
                    # The stream emits various event types; we watch for content
                    if hasattr(event, "choices") and event.choices:
                        delta = event.choices[0].delta
                        if hasattr(delta, "content") and delta.content:
                            if not got_first:
                                first_token_time = time.time()
                                got_first = True
                            output_tokens += 1
        else:
            response = await client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=max_tokens,
                stream=False,
            )
            if response.usage:
                output_tokens = response.usage.completion_tokens or 0

    except Exception as e:
        success = False
        error = str(e)

    total_latency = time.time() - start
    ttft = (first_token_time - start) if first_token_time else None

    return {
        "request_id":        request_id,
        "start_time":        start,
        "total_latency":     round(total_latency, 4),
        "time_to_first_token": round(ttft, 4) if ttft else None,
        "output_tokens":     output_tokens,
        "success":           success,
        "error":             error,
        "prompt_len":        len(prompt),
    }


async def run_level(concurrency, n_requests, model, prompts, max_tokens, use_stream, base_url, api_key):
    """Run n_requests with at most `concurrency` in flight at once."""
    client = AsyncOpenAI(base_url=f"{base_url.rstrip('/')}/v1", api_key=api_key)
    semaphore = asyncio.Semaphore(concurrency)

    async def bounded(req_id):
        prompt = prompts[req_id % len(prompts)]
        async with semaphore:
            return await run_request(client, model, prompt, max_tokens, use_stream, req_id)

    tasks = [bounded(i) for i in range(n_requests)]
    wall_start = time.time()
    results = await asyncio.gather(*tasks)
    wall_time = time.time() - wall_start
    return results, wall_time


def percentile(values, p):
    if not values:
        return None
    sorted_v = sorted(values)
    idx = int(len(sorted_v) * p / 100)
    idx = min(idx, len(sorted_v) - 1)
    return round(sorted_v[idx], 4)


def summarise(results, wall_time, concurrency, model):
    latencies  = [r["total_latency"] for r in results if r["success"]]
    ttfts      = [r["time_to_first_token"] for r in results
                  if r["success"] and r["time_to_first_token"] is not None]
    successes  = sum(1 for r in results if r["success"])
    failures   = len(results) - successes

    summary = {
        "concurrency":       concurrency,
        "model":             model,
        "total_requests":    len(results),
        "success_count":     successes,
        "failure_count":     failures,
        "failure_rate_pct":  round(failures / max(len(results), 1) * 100, 2),
        "wall_time_s":       round(wall_time, 3),
        "requests_per_sec":  round(successes / max(wall_time, 0.001), 2),
        "avg_latency_s":     round(statistics.mean(latencies), 4) if latencies else None,
        "p50_latency_s":     percentile(latencies, 50),
        "p95_latency_s":     percentile(latencies, 95),
        "p99_latency_s":     percentile(latencies, 99),
        "avg_ttft_s":        round(statistics.mean(ttfts), 4) if ttfts else None,
        "p95_ttft_s":        percentile(ttfts, 95),
    }
    return summary


# ── Main ──────────────────────────────────────────────────────────────────
async def main():
    print(f"\n{'═'*60}")
    print(f"  Concurrency benchmark")
    print(f"  Model    : {args.model}")
    print(f"  Endpoint : {args.base_url}/v1")
    print(f"  Levels   : {args.concurrency}")
    print(f"  Requests : {args.requests} per level")
    print(f"  Streaming: {args.stream}")
    print(f"  Output   : {output_jsonl}")
    print(f"{'═'*60}\n")

    all_summaries = []

    for level in args.concurrency:
        print(f"── Concurrency {level:>3} ── ({args.requests} requests) ────────────────")
        results, wall = await run_level(
            concurrency=level,
            n_requests=args.requests,
            model=args.model,
            prompts=prompts,
            max_tokens=args.max_tokens,
            use_stream=args.stream,
            base_url=args.base_url,
            api_key=args.api_key,
        )

        summary = summarise(results, wall, level, args.model)
        all_summaries.append(summary)

        # Write raw results to JSONL (append)
        with open(output_jsonl, "a") as f:
            for r in results:
                r["concurrency_level"] = level
                r["model"] = args.model
                f.write(json.dumps(r) + "\n")

        # Print per-level summary
        print(f"  Total requests  : {summary['total_requests']}")
        print(f"  Success / Fail  : {summary['success_count']} / {summary['failure_count']}")
        print(f"  Wall time       : {summary['wall_time_s']}s")
        print(f"  Requests/sec    : {summary['requests_per_sec']}")
        print(f"  Avg latency     : {summary['avg_latency_s']}s")
        print(f"  p50 latency     : {summary['p50_latency_s']}s")
        print(f"  p95 latency     : {summary['p95_latency_s']}s")
        print(f"  p99 latency     : {summary['p99_latency_s']}s")
        if summary["avg_ttft_s"]:
            print(f"  Avg TTFT        : {summary['avg_ttft_s']}s")
            print(f"  p95 TTFT        : {summary['p95_ttft_s']}s")
        print()

    # Save summary JSON
    full_summary = {
        "timestamp":   datetime.now().isoformat(),
        "model":       args.model,
        "base_url":    args.base_url,
        "max_tokens":  args.max_tokens,
        "streaming":   args.stream,
        "levels":      all_summaries,
    }
    with open(output_summary, "w") as f:
        json.dump(full_summary, f, indent=2)

    print(f"{'═'*60}")
    print(f"  Raw results  → {output_jsonl}")
    print(f"  Summary JSON → {output_summary}")
    print(f"{'═'*60}\n")


asyncio.run(main())
