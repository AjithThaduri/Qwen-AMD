#!/usr/bin/env python3
"""
Aggregate load test summary JSON files into Markdown + CSV reports.
Does not embed secrets; API key is referenced only as a fixed testing label.
"""

from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_summaries(summaries_dir: Path) -> list[dict]:
    rows: list[dict] = []
    for p in sorted(summaries_dir.glob("*.json")):
        try:
            rows.append(json.loads(p.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError) as e:
            print(f"⚠ Skip {p}: {e}", file=sys.stderr)
    return rows


def pick_numeric(rows: list[dict], key: str, *, mode: str) -> tuple[dict | None, float | None]:
    best: dict | None = None
    best_val: float | None = None
    for r in rows:
        v = r.get(key)
        if v is None:
            continue
        try:
            fv = float(v)
        except (TypeError, ValueError):
            continue
        if best_val is None:
            best, best_val = r, fv
            continue
        if mode == "max" and fv > best_val:
            best, best_val = r, fv
        elif mode == "min" and fv < best_val:
            best, best_val = r, fv
    return best, best_val


def fmt_test(r: dict | None) -> str:
    if not r:
        return "n/a"
    return f"`{r.get('label', '')}` (throughput {r.get('approx_output_tokens_per_sec')} tok/s)"


def fmt_latency(r: dict | None) -> str:
    if not r:
        return "n/a"
    return f"`{r.get('label', '')}` (avg latency {r.get('latency_avg_sec')} s)"


def fmt_p95(r: dict | None) -> str:
    if not r:
        return "n/a"
    return f"`{r.get('label', '')}` (p95 {r.get('latency_p95_sec')} s)"


def md_table(rows: list[dict]) -> str:
    headers = [
        "label",
        "stream",
        "concurrency",
        "requests",
        "max_tokens",
        "success_count",
        "failure_count",
        "failure_rate",
        "approx_output_tokens_per_sec",
        "latency_avg_sec",
        "latency_p95_sec",
        "latency_p99_sec",
        "ttft_avg_sec",
        "ttft_p95_sec",
    ]
    lines = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    for r in rows:
        cells = [str(r.get(h, "")) for h in headers]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate loadtest Markdown + CSV from a run directory")
    ap.add_argument("run_dir", type=Path, help="Path to run_YYYYMMDD_HHMMSS directory")
    args = ap.parse_args()
    run_dir: Path = args.run_dir.resolve()
    summaries_dir = run_dir / "summaries"
    reports_dir = run_dir / "reports"
    if not summaries_dir.is_dir():
        print(f"✗ Not a directory: {summaries_dir}", file=sys.stderr)
        sys.exit(1)
    reports_dir.mkdir(parents=True, exist_ok=True)

    rows = load_summaries(summaries_dir)
    if not rows:
        print(f"✗ No summary JSON files in {summaries_dir}", file=sys.stderr)
        sys.exit(1)

    sample = rows[0]
    reported_base = sample.get("api_base_url") or "https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1"
    reported_model = sample.get("model") or "qwen3.6-35b-a3b-awq"
    api_note = "Authentication used the shared development key `dev-test-key` for this test run only."

    best_tp, tp_val = pick_numeric(rows, "approx_output_tokens_per_sec", mode="max")
    best_lat, lat_val = pick_numeric(rows, "latency_avg_sec", mode="min")
    worst_p95, p95_val = pick_numeric(rows, "latency_p95_sec", mode="max")

    stream_rows = [r for r in rows if r.get("stream") is True]
    nostream_rows = [r for r in rows if r.get("stream") is False]

    high_fail = [r for r in rows if float(r.get("failure_rate") or 0) > 0.2]

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    md_lines = [
        "# Qwen MI300X vLLM Load Test Report",
        "",
        f"**Generated:** {now}",
        "",
        "## Target environment",
        "",
        f"- **API base URL:** `{reported_base}`",
        f"- **Model:** `{reported_model}`",
        f"- **Backend:** vLLM on AMD MI300X (RunPod); max_model_len 8192 on server.",
        f"- **Client:** macOS load generator (this repo). {api_note}",
        "",
        "## Environment assumptions",
        "",
        "- Network path includes RunPod HTTP proxy; latencies include WAN effects.",
        "- Output token counts are approximated as `output_chars // 4` per request.",
        "- Non-streaming summaries set TTFT equal to total latency by convention (see per-summary `ttft_note`).",
        "- Per-request timeout was enforced by the benchmark client; failed requests are counted but do not stop the matrix.",
        "",
        "## Summary table (all tests)",
        "",
        md_table(rows),
        "",
        "## Highlights",
        "",
        f"- **Best throughput (approx output tok/s, wall clock):** {fmt_test(best_tp)}",
        f"- **Best average end-to-end latency:** {fmt_latency(best_lat)}",
        f"- **Worst p95 latency:** {fmt_p95(worst_p95)}",
        "",
        "## Streaming vs non-streaming",
        "",
        "### Streaming (`stream: true`)",
        md_table(stream_rows) if stream_rows else "_No streaming rows._",
        "",
        "### Non-streaming (`stream: false`)",
        md_table(nostream_rows) if nostream_rows else "_No non-streaming rows._",
        "",
        "## Failure analysis",
        "",
    ]
    if high_fail:
        md_lines.append("Tests with **failure_rate > 20%** (matrix continued):")
        md_lines.append("")
        for r in high_fail:
            md_lines.append(
                f"- `{r.get('label')}`: failure_rate={r.get('failure_rate')}, "
                f"errors_top_5={json.dumps(r.get('errors_top_5'), ensure_ascii=False)}"
            )
        md_lines.append("")
    else:
        md_lines.append("No test exceeded a 20% failure rate.")
        md_lines.append("")

    md_lines.extend(
        [
            "## Recommended production limits",
            "",
            "- Treat **p95/p99 latency** and **failure_rate** under sustained concurrency as primary SLO drivers.",
            "- Prefer **streaming** for user-perceived latency when TTFT matters; compare decode throughput separately.",
            "- Cap **max_tokens** and concurrent streams per user to keep KV footprint predictable on a single MI300X.",
            "",
            "## Recommendation for ~50 concurrent users",
            "",
            "- From the matrix row closest to 50 concurrent clients, compare throughput vs p95 latency.",
            "- If p95 latency or failures rise sharply near 50, queue or autoscale before adding users on one GPU.",
            "- Monitor **prefill vs decode** on the server (e.g. `rocm-smi` during load); client TTFT spikes often track prefill contention.",
            "",
            "## Notes (TTFT, p95/p99, throughput, failures)",
            "",
            "- **TTFT:** streaming TTFT is first non-empty token; non-streaming TTFT matches full response time in this harness.",
            "- **p95/p99:** computed with linear interpolation on successful requests.",
            "- **Throughput:** `approx_output_tokens_per_sec` divides total successful output tokens by total wall time for the batch.",
            "- **Failure rate:** failures include timeouts and HTTP/API errors; inspect `errors_top_5` per test in summary JSON.",
            "",
            "## Raw artifacts",
            "",
            f"- Raw JSONL: `{run_dir / 'raw'}`",
            f"- Summary JSON: `{summaries_dir}`",
            "",
        ]
    )

    md_path = reports_dir / "loadtest_report.md"
    md_path.write_text("\n".join(md_lines), encoding="utf-8")

    # CSV: flatten for spreadsheet use
    csv_path = reports_dir / "loadtest_summary.csv"
    exclude = {"errors_top_5"}
    all_keys: list[str] = []
    for r in rows:
        for k in r:
            if k not in exclude and k not in all_keys:
                all_keys.append(k)
    err_key = "errors_top_5_json"
    fieldnames = all_keys + [err_key]
    with csv_path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            flat = {k: r.get(k, "") for k in all_keys}
            flat[err_key] = json.dumps(r.get("errors_top_5"), ensure_ascii=False)
            w.writerow(flat)

    print(f"Wrote {md_path}")
    print(f"Wrote {csv_path}")


if __name__ == "__main__":
    main()
