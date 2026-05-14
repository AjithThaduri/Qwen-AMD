#!/usr/bin/env python3
"""
Async OpenAI-compatible load tester for vLLM (chat completions).

Non-streaming TTFT: set equal to total latency so percentiles are defined;
see summary field non_streaming_ttft_equals_latency.
Streaming time_to_last_token_sec: wall time from first non-empty token to stream end (decode phase).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

def utc_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def mean(vals: list[float]) -> float:
    return float(sum(vals) / len(vals)) if vals else 0.0


def percentile_sorted(sorted_vals: list[float], p: float) -> float | None:
    """Linear interpolation percentile on sorted non-empty list. p in [0, 100]."""
    if not sorted_vals:
        return None
    xs = sorted_vals
    n = len(xs)
    if n == 1:
        return float(xs[0])
    if p <= 0:
        return float(xs[0])
    if p >= 100:
        return float(xs[-1])
    k = (n - 1) * (p / 100.0)
    f = int(math.floor(k))
    c = int(math.ceil(k))
    if f == c:
        return float(xs[f])
    d0 = xs[f] * (c - k)
    d1 = xs[c] * (k - f)
    return float(d0 + d1)


def load_prompt(path: Path) -> str:
    if not path.exists():
        print(f"✗ Prompt file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return path.read_text(encoding="utf-8").strip()


async def one_request(
    *,
    client: Any,
    model: str,
    prompt: str,
    request_id: int,
    label: str,
    prompt_file: str,
    stream: bool,
    max_tokens: int,
    temperature: float,
    timeout_sec: float,
    sem: asyncio.Semaphore,
) -> dict[str, Any]:
    """Run a single chat completion; return result dict (never raises)."""
    result: dict[str, Any] = {
        "request_id": request_id,
        "label": label,
        "prompt_file": prompt_file,
        "stream": stream,
        "success": False,
        "error": None,
        "start_wall_time": None,
        "end_wall_time": None,
        "latency_sec": None,
        "time_to_first_token_sec": None,
        "time_to_last_token_sec": None,
        "output_chars": 0,
        "approx_output_tokens": 0,
        "approx_tokens_per_sec": None,
        "http_api_error": None,
    }

    async with sem:
        t0_wall = utc_iso()
        result["start_wall_time"] = t0_wall
        t_start = time.perf_counter()
        output_chars = 0
        ttft: float | None = None
        ttl_decode: float | None = None
        err_str: str | None = None
        api_err: str | None = None

        try:
            if stream:
                api_stream = await client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=max_tokens,
                    temperature=temperature,
                    stream=True,
                    timeout=timeout_sec,
                )
                first_token_perf: float | None = None
                async for chunk in api_stream:
                    choice = chunk.choices[0] if chunk.choices else None
                    if not choice:
                        continue
                    delta = choice.delta
                    content = getattr(delta, "content", None) if delta else None
                    if content:
                        if first_token_perf is None:
                            first_token_perf = time.perf_counter()
                        output_chars += len(content)
                t_end = time.perf_counter()
                latency = t_end - t_start
                if first_token_perf is not None:
                    ttft = first_token_perf - t_start
                    ttl_decode = t_end - first_token_perf
                else:
                    ttft = None
                    ttl_decode = None
            else:
                resp = await client.chat.completions.create(
                    model=model,
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=max_tokens,
                    temperature=temperature,
                    stream=False,
                    timeout=timeout_sec,
                )
                t_end = time.perf_counter()
                latency = t_end - t_start
                msg = resp.choices[0].message if resp.choices else None
                content = getattr(msg, "content", None) or ""
                output_chars = len(content)
                # TTFT equals full response latency for non-streaming (documented in summary).
                ttft = latency
                ttl_decode = None

            approx_tokens = output_chars // 4
            tps = (approx_tokens / latency) if latency and latency > 0 else None

            result.update(
                {
                    "success": True,
                    "end_wall_time": utc_iso(),
                    "latency_sec": round(latency, 6),
                    "time_to_first_token_sec": round(ttft, 6) if ttft is not None else None,
                    "time_to_last_token_sec": round(ttl_decode, 6) if ttl_decode is not None else None,
                    "output_chars": output_chars,
                    "approx_output_tokens": approx_tokens,
                    "approx_tokens_per_sec": round(tps, 4) if tps is not None else None,
                }
            )
        except Exception as e:  # noqa: BLE001 — record all failures
            t_end = time.perf_counter()
            latency = t_end - t_start
            err_str = f"{type(e).__name__}: {e}"
            api_err = err_str
            body = getattr(e, "body", None)
            if body is not None:
                api_err = f"{err_str} | body={body}"
            result.update(
                {
                    "success": False,
                    "error": err_str,
                    "http_api_error": api_err,
                    "end_wall_time": utc_iso(),
                    "latency_sec": round(latency, 6),
                    "time_to_first_token_sec": None,
                    "time_to_last_token_sec": None,
                    "output_chars": output_chars,
                    "approx_output_tokens": output_chars // 4,
                    "approx_tokens_per_sec": None,
                }
            )

    return result


def build_summary(
    *,
    api_base_url: str,
    model: str,
    label: str,
    prompt_file: str,
    concurrency: int,
    requests_n: int,
    max_tokens: int,
    stream: bool,
    temperature: float,
    timeout_sec: float,
    rows: list[dict[str, Any]],
    total_wall_time_sec: float,
) -> dict[str, Any]:
    successes = [r for r in rows if r.get("success")]
    failures = [r for r in rows if not r.get("success")]
    success_count = len(successes)
    failure_count = len(failures)
    failure_rate = failure_count / requests_n if requests_n else 0.0

    latencies = [r["latency_sec"] for r in successes if r.get("latency_sec") is not None]
    lat_sorted = sorted(latencies)

    ttft_vals = [
        r["time_to_first_token_sec"]
        for r in successes
        if r.get("time_to_first_token_sec") is not None
    ]
    ttft_sorted = sorted(ttft_vals)

    per_req_tps = [
        r["approx_tokens_per_sec"]
        for r in successes
        if r.get("approx_tokens_per_sec") is not None
    ]

    err_counter: Counter[str] = Counter()
    for r in failures:
        e = r.get("error") or "unknown"
        err_counter[str(e)] += 1
    errors_top_5 = [{"error": e, "count": c} for e, c in err_counter.most_common(5)]

    approx_total_out = sum(r.get("approx_output_tokens") or 0 for r in successes)
    out_tps = (approx_total_out / total_wall_time_sec) if total_wall_time_sec > 0 else None
    rps = requests_n / total_wall_time_sec if total_wall_time_sec > 0 else None

    def pct(arr: list[float], p: float) -> float | None:
        return percentile_sorted(arr, p) if arr else None

    summary: dict[str, Any] = {
        "api_base_url": api_base_url,
        "model": model,
        "label": label,
        "prompt_file": prompt_file,
        "concurrency": concurrency,
        "requests": requests_n,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "timeout_sec": timeout_sec,
        "stream": stream,
        "non_streaming_ttft_equals_latency": (not stream),
        "ttft_note": (
            "Non-streaming: time_to_first_token_sec equals full response latency by convention."
            if not stream
            else "Streaming: TTFT is time to first non-empty delta; time_to_last_token_sec is decode duration (first token to stream end)."
        ),
        "success_count": success_count,
        "failure_count": failure_count,
        "failure_rate": round(failure_rate, 6),
        "total_wall_time_sec": round(total_wall_time_sec, 6),
        "requests_per_sec": round(rps, 4) if rps is not None else None,
        "approx_total_output_tokens": approx_total_out,
        "approx_output_tokens_per_sec": round(out_tps, 4) if out_tps is not None else None,
        "latency_avg_sec": round(mean(lat_sorted), 6) if lat_sorted else None,
        "latency_min_sec": round(min(lat_sorted), 6) if lat_sorted else None,
        "latency_max_sec": round(max(lat_sorted), 6) if lat_sorted else None,
        "latency_p50_sec": round(pct(lat_sorted, 50), 6) if lat_sorted else None,
        "latency_p90_sec": round(pct(lat_sorted, 90), 6) if lat_sorted else None,
        "latency_p95_sec": round(pct(lat_sorted, 95), 6) if lat_sorted else None,
        "latency_p99_sec": round(pct(lat_sorted, 99), 6) if lat_sorted else None,
        "ttft_avg_sec": round(mean(ttft_sorted), 6) if ttft_sorted else None,
        "ttft_min_sec": round(min(ttft_sorted), 6) if ttft_sorted else None,
        "ttft_max_sec": round(max(ttft_sorted), 6) if ttft_sorted else None,
        "ttft_p50_sec": round(pct(ttft_sorted, 50), 6) if ttft_sorted else None,
        "ttft_p90_sec": round(pct(ttft_sorted, 90), 6) if ttft_sorted else None,
        "ttft_p95_sec": round(pct(ttft_sorted, 95), 6) if ttft_sorted else None,
        "ttft_p99_sec": round(pct(ttft_sorted, 99), 6) if ttft_sorted else None,
        "per_request_tokens_per_sec_avg": round(mean(per_req_tps), 4) if per_req_tps else None,
        "errors_top_5": errors_top_5,
        "generated_at_utc": utc_iso(),
    }
    return summary


async def run_benchmark(args: argparse.Namespace) -> None:
    try:
        from openai import AsyncOpenAI
    except ImportError:
        print("✗ openai package not installed. Run: python3 -m pip install --upgrade openai", file=sys.stderr)
        sys.exit(1)

    prompt_path = Path(args.prompt_file)
    prompt = load_prompt(prompt_path)
    prompt_file_str = str(prompt_path)

    raw_path = Path(args.output_raw)
    summary_path = Path(args.output_summary)
    raw_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)

    client = AsyncOpenAI(
        base_url=args.base_url.rstrip("/"),
        api_key=args.api_key,
        timeout=args.timeout,
        max_retries=0,
    )

    sem = asyncio.Semaphore(args.concurrency)
    requests_n = args.requests

    wall_start = time.perf_counter()
    tasks = [
        one_request(
            client=client,
            model=args.model,
            prompt=prompt,
            request_id=i + 1,
            label=args.label,
            prompt_file=prompt_file_str,
            stream=args.stream,
            max_tokens=args.max_tokens,
            temperature=args.temperature,
            timeout_sec=args.timeout,
            sem=sem,
        )
        for i in range(requests_n)
    ]
    rows = await asyncio.gather(*tasks)
    total_wall = time.perf_counter() - wall_start

    with raw_path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    summary = build_summary(
        api_base_url=args.base_url.rstrip("/"),
        model=args.model,
        label=args.label,
        prompt_file=prompt_file_str,
        concurrency=args.concurrency,
        requests_n=requests_n,
        max_tokens=args.max_tokens,
        stream=args.stream,
        temperature=args.temperature,
        timeout_sec=args.timeout,
        rows=rows,
        total_wall_time_sec=total_wall,
    )
    summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")

    print(json.dumps(summary, indent=2, ensure_ascii=False))

    warn = ""
    if summary["failure_rate"] > 0.2:
        warn = f"\n⚠ High failure_rate: {summary['failure_rate']:.1%} (continuing per matrix policy)\n"
    if warn:
        print(warn, file=sys.stderr)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="OpenAI-compatible async load test (vLLM)")
    p.add_argument("--base-url", required=True, help="API base URL including /v1")
    p.add_argument("--api-key", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--concurrency", type=int, default=1)
    p.add_argument("--requests", type=int, default=1)
    p.add_argument("--max-tokens", type=int, default=256)
    p.add_argument("--temperature", type=float, default=0.0)
    p.add_argument("--prompt-file", required=True)
    p.add_argument("--output-raw", required=True)
    p.add_argument("--output-summary", required=True)
    p.add_argument("--stream", action=argparse.BooleanOptionalAction, default=True)
    p.add_argument("--timeout", type=float, default=600.0, help="Per-request HTTP timeout (seconds)")
    p.add_argument("--label", default="run", help="Logical test label for aggregation")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    asyncio.run(run_benchmark(args))


if __name__ == "__main__":
    main()
