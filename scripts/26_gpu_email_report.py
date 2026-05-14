#!/usr/bin/env python3
"""
26_gpu_email_report.py
Run this ON THE RUNPOD POD.

Modes:
  python3 26_gpu_email_report.py --daily   # daily morning report (cron)
  python3 26_gpu_email_report.py --alert   # VRAM alert (called by monitor)
  python3 26_gpu_email_report.py --test    # verify SMTP

Config: /workspace/configs/email.conf  (never committed to git)
"""

import argparse
import os
import re
import smtplib
import subprocess
import sys
from datetime import datetime, timezone
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from urllib.request import urlopen
from urllib.error import URLError

CONFIG_PATH = Path("/workspace/configs/email.conf")
DAILY_LOG_DIR = Path("/workspace/gpu_stats/daily")
METRICS_URL = "http://localhost:8000/metrics"
ERROR_STATE_FILE = Path("/tmp/vllm_error_alert_state")


# ── config ────────────────────────────────────────────────────────────────────

def load_config():
    if not CONFIG_PATH.exists():
        print(f"ERROR: Config not found at {CONFIG_PATH}")
        sys.exit(1)
    cfg = {}
    for line in CONFIG_PATH.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip()
    return cfg


# ── data collection ───────────────────────────────────────────────────────────

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return ""


def _parse_rocmsmi_value(key_pattern, output):
    """Extract the last colon-separated field from a rocm-smi verbose line."""
    for line in output.splitlines():
        if key_pattern.lower() in line.lower():
            # Split on ': ' and take the last token
            parts = re.split(r':\s*', line)
            if len(parts) >= 2:
                val = parts[-1].strip().rstrip('%').rstrip('c').rstrip('C').rstrip('W').strip()
                if val:
                    return val
    return "?"


def get_gpu_stats():
    stats = {}

    vram_out  = run("rocm-smi --showmemuse 2>/dev/null")
    temp_out  = run("rocm-smi --showtemp  2>/dev/null")
    use_out   = run("rocm-smi --showuse   2>/dev/null")
    power_out = run("rocm-smi --showpower 2>/dev/null")

    stats["vram_pct"]  = _parse_rocmsmi_value("GPU Memory Allocated", vram_out)
    stats["temp_c"]    = _parse_rocmsmi_value("Temperature (Sensor junction)", temp_out)
    stats["gpu_pct"]   = _parse_rocmsmi_value("GPU use", use_out)
    stats["power_w"]   = _parse_rocmsmi_value("Current Socket Graphics Package Power", power_out)
    stats["raw"]       = run("rocm-smi 2>/dev/null")

    return stats


def get_peak_stats_today():
    """Read today's daily log and return peak VRAM/GPU/temp from it."""
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    log_file = DAILY_LOG_DIR / f"{today}.log"
    peaks = {"vram_pct": "—", "gpu_pct": "—", "temp_c": "—", "power_w": "—"}

    if not log_file.exists():
        return peaks

    text = log_file.read_text()
    vram_vals, gpu_vals, temp_vals, power_vals = [], [], [], []

    for line in text.splitlines():
        v = _try_float(_parse_rocmsmi_value("GPU Memory Allocated", line + "\n"))
        if v is not None:
            vram_vals.append(v)
        g = _try_float(_parse_rocmsmi_value("GPU use", line + "\n"))
        if g is not None:
            gpu_vals.append(g)
        t = _try_float(_parse_rocmsmi_value("Temperature (Sensor junction)", line + "\n"))
        if t is not None:
            temp_vals.append(t)
        p = _try_float(_parse_rocmsmi_value("Current Socket Graphics Package Power", line + "\n"))
        if p is not None:
            power_vals.append(p)

    if vram_vals:  peaks["vram_pct"]  = str(max(vram_vals))
    if gpu_vals:   peaks["gpu_pct"]   = str(max(gpu_vals))
    if temp_vals:  peaks["temp_c"]    = str(max(temp_vals))
    if power_vals: peaks["power_w"]   = str(max(power_vals))

    return peaks


def _try_float(s):
    try:
        return float(s)
    except Exception:
        return None


def get_vllm_status():
    pid = run("pgrep -f 'vllm serve' | head -1")
    if pid:
        uptime = run(f"ps -o etime= -p {pid} 2>/dev/null").strip()
        return {"running": True, "pid": pid, "uptime": uptime}
    return {"running": False, "pid": None, "uptime": None}


def get_disk_usage():
    workspace = run("df -h /workspace 2>/dev/null | tail -1 | awk '{print $2, $3, $4, $5}'")
    root      = run("df -h / 2>/dev/null | tail -1 | awk '{print $2, $3, $4, $5}'")
    return {"workspace": workspace, "root": root}


def get_vllm_metrics():
    """Fetch Prometheus /metrics and return request/token counts."""
    result = {
        "requests_ok":     "—",
        "requests_failed": "—",
        "tokens_generated":"—",
        "tokens_prompt":   "—",
        "running_requests":"—",
        "waiting_requests":"—",
    }
    try:
        with urlopen(METRICS_URL, timeout=3) as r:
            text = r.read().decode()
    except (URLError, Exception):
        return result

    def _prometheus_sum(name, text):
        total = 0.0
        found = False
        for line in text.splitlines():
            if line.startswith(name + "{") or line.startswith(name + " "):
                m = re.search(r'\s+([\d.eE+\-]+)\s*$', line)
                if m:
                    total += float(m.group(1))
                    found = True
        return f"{int(total):,}" if found else "—"

    def _prometheus_gauge(name, text):
        for line in text.splitlines():
            if line.startswith(name + "{") or line.startswith(name + " "):
                m = re.search(r'\s+([\d.eE+\-]+)\s*$', line)
                if m:
                    return f"{int(float(m.group(1)))}"
        return "—"

    result["requests_ok"]      = _prometheus_sum("vllm:request_success_total", text)
    result["requests_failed"]  = _prometheus_sum("vllm:request_failure_total", text)
    result["tokens_generated"] = _prometheus_sum("vllm:generation_tokens_total", text)
    result["tokens_prompt"]    = _prometheus_sum("vllm:prompt_tokens_total", text)
    result["running_requests"] = _prometheus_gauge("vllm:num_requests_running", text)
    result["waiting_requests"] = _prometheus_gauge("vllm:num_requests_waiting", text)
    return result


# ── HTML style ────────────────────────────────────────────────────────────────

STYLE = """
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         background: #f0f2f5; margin: 0; padding: 24px; color: #1a1a2e; }
  .wrapper { max-width: 700px; margin: 0 auto; }

  .header { background: linear-gradient(135deg, #1a1a2e 0%, #16213e 60%, #0f3460 100%);
            border-radius: 14px 14px 0 0; padding: 32px 36px 28px; color: white; }
  .header .tag { font-size: 11px; font-weight: 700; letter-spacing: 0.12em;
                 text-transform: uppercase; opacity: 0.6; margin-bottom: 8px; }
  .header h1 { margin: 0 0 6px; font-size: 24px; font-weight: 800; }
  .header p  { margin: 0; font-size: 13px; opacity: 0.7; }

  .card { background: white; padding: 28px 36px; border-bottom: 1px solid #edf0f5; }
  .card:last-of-type { border-radius: 0 0 14px 14px; border-bottom: none; }
  .section-title { font-size: 11px; font-weight: 700; letter-spacing: 0.1em;
                   text-transform: uppercase; color: #94a3b8; margin: 0 0 18px; }

  /* 4-up metric grid */
  .grid4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
  .mbox { background: #f8fafc; border: 1px solid #e8ecf2;
          border-radius: 10px; padding: 16px 12px; text-align: center; }
  .mbox .val { font-size: 26px; font-weight: 800; color: #0f3460; line-height: 1; }
  .mbox .unit { font-size: 13px; font-weight: 600; color: #64748b; }
  .mbox .lbl { font-size: 11px; color: #94a3b8; margin-top: 6px; }
  .mbox.warn .val { color: #d97706; }
  .mbox.crit .val { color: #dc2626; }
  .mbox.ok   .val { color: #16a34a; }

  /* 2-col comparison grid (current vs peak) */
  .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-top: 20px; }
  .col-label { font-size: 11px; font-weight: 700; text-transform: uppercase;
               letter-spacing: 0.08em; margin-bottom: 10px; }
  .col-label.current { color: #3b82f6; }
  .col-label.peak    { color: #f59e0b; }

  table { width: 100%; border-collapse: collapse; font-size: 13.5px; }
  th { background: #f8fafc; padding: 9px 14px; text-align: left;
       font-weight: 600; color: #64748b; border-bottom: 2px solid #e8ecf2;
       font-size: 12px; }
  td { padding: 9px 14px; border-bottom: 1px solid #f1f4f9; color: #334155; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #fafbfc; }

  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px;
           font-size: 11.5px; font-weight: 700; }
  .badge-ok   { background: #dcfce7; color: #15803d; }
  .badge-warn { background: #fef3c7; color: #b45309; }
  .badge-crit { background: #fee2e2; color: #b91c1c; }
  .badge-down { background: #f1f5f9; color: #64748b; }
  .badge-up   { background: #dbeafe; color: #1d4ed8; }

  .stat-row { display: flex; justify-content: space-between;
              padding: 8px 0; border-bottom: 1px solid #f1f4f9; font-size: 13.5px; }
  .stat-row:last-child { border-bottom: none; }
  .stat-key { color: #64748b; }
  .stat-val { font-weight: 600; color: #1e293b; }

  .alert-box { background: #fff1f2; border: 1.5px solid #fca5a5;
               border-radius: 10px; padding: 18px 20px; margin-bottom: 18px; }
  .alert-box h3 { margin: 0 0 6px; color: #dc2626; font-size: 15px; }
  .alert-box p  { margin: 0; color: #7f1d1d; font-size: 13.5px; }

  pre { background: #0f172a; color: #94a3b8; border-radius: 10px;
        padding: 16px; font-size: 12px; overflow-x: auto;
        white-space: pre; font-family: 'JetBrains Mono', 'Fira Code', monospace; }

  .divider { border: none; border-top: 1px solid #e8ecf2; margin: 20px 0; }

  .footer { text-align: center; padding: 18px; font-size: 12px; color: #94a3b8;
            background: white; border-radius: 0 0 14px 14px; }
  .footer a { color: #3b82f6; text-decoration: none; }
</style>
"""


# ── helpers ───────────────────────────────────────────────────────────────────

def vram_badge(pct_str):
    try:
        p = float(pct_str)
        if p >= 90:   return f'<span class="badge badge-crit">{p:.0f}% CRITICAL</span>'
        if p >= 85:   return f'<span class="badge badge-warn">{p:.0f}% WARNING</span>'
        return             f'<span class="badge badge-ok">{p:.0f}% OK</span>'
    except Exception:
        return f'<span class="badge badge-down">{pct_str}</span>'


def temp_badge(t_str):
    try:
        t = float(t_str)
        if t >= 90: return f'<span class="badge badge-crit">{t:.0f} °C</span>'
        if t >= 75: return f'<span class="badge badge-warn">{t:.0f} °C</span>'
        return           f'<span class="badge badge-ok">{t:.0f} °C</span>'
    except Exception:
        return f'<span class="badge badge-down">{t_str}</span>'


def mbox_class(label, val_str):
    label = label.lower()
    try:
        v = float(val_str)
        if "vram" in label or "gpu" in label:
            if v >= 90: return "crit"
            if v >= 75: return "warn"
            return "ok"
        if "temp" in label:
            if v >= 90: return "crit"
            if v >= 75: return "warn"
            return "ok"
    except Exception:
        pass
    return ""


def metric_box(label, val, unit=""):
    cls = mbox_class(label, val)
    return f"""
    <div class="mbox {cls}">
      <div class="val">{val}</div>
      <div class="unit">{unit}</div>
      <div class="lbl">{label}</div>
    </div>"""


def disk_table(disk):
    def row(mount, data):
        parts = data.split()
        cols = parts + [""] * (4 - len(parts))
        return f"<tr><td><b>{mount}</b></td>{''.join(f'<td>{c}</td>' for c in cols[:4])}</tr>"
    return f"""
    <table>
      <tr><th>Mount</th><th>Total</th><th>Used</th><th>Free</th><th>Use%</th></tr>
      {row('/workspace', disk['workspace'])}
      {row('/ (root)', disk['root'])}
    </table>"""


# ── HTML builders ─────────────────────────────────────────────────────────────

def build_daily_html(gpu, peaks, vllm, disk, metrics, now):
    vllm_badge = ('<span class="badge badge-up">● Running</span>' if vllm["running"]
                  else '<span class="badge badge-down">● Stopped</span>')
    uptime_str = f"PID {vllm['pid']} · uptime {vllm['uptime']}" if vllm["running"] else "Not running"

    current_grid = f"""
    <div class="grid4">
      {metric_box("VRAM Used", gpu['vram_pct'], "%")}
      {metric_box("GPU Compute", gpu['gpu_pct'], "%")}
      {metric_box("Die Temp", gpu['temp_c'], "°C")}
      {metric_box("Power Draw", gpu['power_w'], "W")}
    </div>"""

    peak_grid = f"""
    <div class="grid4">
      {metric_box("VRAM Peak", peaks['vram_pct'], "%")}
      {metric_box("GPU Peak", peaks['gpu_pct'], "%")}
      {metric_box("Max Temp", peaks['temp_c'], "°C")}
      {metric_box("Max Power", peaks['power_w'], "W")}
    </div>"""

    requests_section = f"""
    <div class="card">
      <p class="section-title">Today's vLLM Request Stats</p>
      <div class="stat-row">
        <span class="stat-key">Successful requests</span>
        <span class="stat-val">{metrics['requests_ok']}</span>
      </div>
      <div class="stat-row">
        <span class="stat-key">Failed requests</span>
        <span class="stat-val">{metrics['requests_failed']}</span>
      </div>
      <div class="stat-row">
        <span class="stat-key">Tokens generated</span>
        <span class="stat-val">{metrics['tokens_generated']}</span>
      </div>
      <div class="stat-row">
        <span class="stat-key">Prompt tokens processed</span>
        <span class="stat-val">{metrics['tokens_prompt']}</span>
      </div>
      <div class="stat-row">
        <span class="stat-key">Requests running now</span>
        <span class="stat-val">{metrics['running_requests']}</span>
      </div>
      <div class="stat-row">
        <span class="stat-key">Requests waiting now</span>
        <span class="stat-val">{metrics['waiting_requests']}</span>
      </div>
    </div>"""

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">{STYLE}</head>
<body><div class="wrapper">

  <div class="header">
    <div class="tag">GPU Monitor · RunPod AMD MI300X</div>
    <h1>Daily GPU Report</h1>
    <p>{now.strftime('%A, %B %d %Y')} &nbsp;·&nbsp; {now.strftime('%H:%M')} UTC &nbsp;·&nbsp; Model: qwen3.6-35b-a3b-awq</p>
  </div>

  <div class="card">
    <p class="section-title">Current Snapshot</p>
    {current_grid}
    <hr class="divider">
    <p class="section-title">Today's Peak (from daily log)</p>
    {peak_grid}
  </div>

  {requests_section}

  <div class="card">
    <p class="section-title">vLLM Server</p>
    <div class="stat-row">
      <span class="stat-key">Status</span>
      <span class="stat-val">{vllm_badge}</span>
    </div>
    <div class="stat-row">
      <span class="stat-key">Process</span>
      <span class="stat-val">{uptime_str}</span>
    </div>
    <div class="stat-row">
      <span class="stat-key">Endpoint</span>
      <span class="stat-val"><code>http://localhost:8000/v1</code></span>
    </div>
  </div>

  <div class="card">
    <p class="section-title">Disk Usage</p>
    {disk_table(disk)}
  </div>

  <div class="card">
    <p class="section-title">rocm-smi Raw Output</p>
    <pre>{gpu['raw']}</pre>
  </div>

  <div class="footer">
    Generated by Qwen-AMD monitoring &nbsp;·&nbsp;
    <a href="https://github.com/AjithThaduri/Qwen-AMD">AjithThaduri/Qwen-AMD</a>
  </div>

</div></body></html>"""


def build_alert_html(gpu, vllm, reason, now):
    try:
        vram = float(gpu["vram_pct"])
        vram_display = f"{vram:.0f}%"
    except Exception:
        vram_display = gpu["vram_pct"]

    uptime_str = (f"Running — PID {vllm['pid']}, uptime {vllm['uptime']}"
                  if vllm["running"] else "NOT RUNNING")

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">{STYLE}</head>
<body><div class="wrapper">

  <div class="header" style="background: linear-gradient(135deg, #7f1d1d 0%, #991b1b 60%, #dc2626 100%);">
    <div class="tag">Alert · RunPod AMD MI300X</div>
    <h1>⚠ VRAM High — {vram_display}</h1>
    <p>{now.strftime('%A, %B %d %Y · %H:%M UTC')}</p>
  </div>

  <div class="card">
    <div class="alert-box">
      <h3>VRAM exceeded 85% alert threshold</h3>
      <p>Current usage: <strong>{vram_display}</strong> &nbsp;·&nbsp; Threshold: 85%</p>
    </div>

    <p class="section-title">GPU State at Alert Time</p>
    <div class="grid4">
      {metric_box("VRAM Used", gpu['vram_pct'], "%")}
      {metric_box("GPU Compute", gpu['gpu_pct'], "%")}
      {metric_box("Die Temp", gpu['temp_c'], "°C")}
      {metric_box("Power Draw", gpu['power_w'], "W")}
    </div>
  </div>

  <div class="card">
    <p class="section-title">Why This Happened</p>
    <p style="color:#334155; font-size:13.5px; margin:0 0 14px">{reason}</p>
    <table>
      <tr><th>Cause</th><th>Explanation</th></tr>
      <tr><td>KV cache pressure</td><td>Long conversations or many concurrent requests fill the KV cache. Model weights use ~24 GB; remaining ~138 GB is KV cache.</td></tr>
      <tr><td>Concurrent load spike</td><td>More simultaneous users than the current <code>--gpu-memory-utilization 0.85</code> allocation allows.</td></tr>
      <tr><td>Single long context</td><td>A request with a very long prompt + output can temporarily spike VRAM above steady-state.</td></tr>
    </table>

    <hr class="divider">
    <p class="section-title">Recommended Actions</p>
    <table>
      <tr><th>Action</th><th>How</th></tr>
      <tr><td>Check live requests</td><td><code>curl http://localhost:8000/metrics | grep vllm:num_requests</code></td></tr>
      <tr><td>Check vLLM log</td><td><code>tmux attach -t vllm</code> (window 0)</td></tr>
      <tr><td>Restart if OOM risk</td><td><code>tmux attach -t vllm</code> → Ctrl+C → re-run serve command</td></tr>
      <tr><td>Reduce context</td><td>Add <code>--max-model-len 16384</code> to vLLM serve to free KV cache headroom</td></tr>
    </table>
  </div>

  <div class="card">
    <p class="section-title">vLLM Server Status</p>
    <div class="stat-row">
      <span class="stat-key">Status</span>
      <span class="stat-val">{uptime_str}</span>
    </div>
    <hr class="divider">
    <p class="section-title">rocm-smi</p>
    <pre>{gpu['raw']}</pre>
  </div>

  <div class="footer">
    Generated by Qwen-AMD monitoring &nbsp;·&nbsp;
    <a href="https://github.com/AjithThaduri/Qwen-AMD">AjithThaduri/Qwen-AMD</a>
  </div>

</div></body></html>"""


# ── error alert helpers ───────────────────────────────────────────────────────

def get_error_delta():
    """
    Compare current failure count from /metrics against last saved value.
    Returns (new_failures, total_failures, error_rate_pct, recent_log_lines).
    Returns None if /metrics is unreachable.
    """
    metrics = get_vllm_metrics()
    if metrics["requests_failed"] == "—":
        return None

    try:
        total_failed = int(metrics["requests_failed"].replace(",", ""))
        total_ok     = int(metrics["requests_ok"].replace(",", "") if metrics["requests_ok"] != "—" else 0)
    except Exception:
        return None

    # Load previous failure count
    prev_failed = 0
    if ERROR_STATE_FILE.exists():
        try:
            prev_failed = int(ERROR_STATE_FILE.read_text().strip())
        except Exception:
            pass

    new_failures = max(0, total_failed - prev_failed)

    # Save current count
    ERROR_STATE_FILE.write_text(str(total_failed))

    total_requests = total_ok + total_failed
    error_rate = (total_failed / total_requests * 100) if total_requests > 0 else 0

    # Pull last 30 lines of vLLM serve log for context
    serve_log = Path("/workspace/serve_awq.log")
    log_lines = ""
    if serve_log.exists():
        lines = serve_log.read_text().splitlines()
        # Filter to lines likely related to errors
        error_lines = [l for l in lines if any(k in l for k in ["ERROR", "error", "400", "500", "Exception", "Traceback", "failed", "Failed"])]
        log_lines = "\n".join(error_lines[-20:]) or "(no error lines found in log)"

    return {
        "new_failures":   new_failures,
        "total_failed":   total_failed,
        "total_ok":       total_ok,
        "error_rate":     round(error_rate, 1),
        "running":        metrics["running_requests"],
        "waiting":        metrics["waiting_requests"],
        "tokens_gen":     metrics["tokens_generated"],
        "log_lines":      log_lines,
    }


def build_error_alert_html(gpu, vllm, err, now):
    uptime_str = (f"Running — PID {vllm['pid']}, uptime {vllm['uptime']}"
                  if vllm["running"] else "NOT RUNNING")

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">{STYLE}</head>
<body><div class="wrapper">

  <div class="header" style="background: linear-gradient(135deg, #1e1b4b 0%, #312e81 60%, #4f46e5 100%);">
    <div class="tag">Alert · RunPod AMD MI300X</div>
    <h1>⚠ Request Errors Detected</h1>
    <p>{now.strftime('%A, %B %d %Y · %H:%M UTC')} &nbsp;·&nbsp; +{err['new_failures']} new failures in last 5 min</p>
  </div>

  <div class="card">
    <div class="alert-box" style="background:#ede9fe; border-color:#a78bfa;">
      <h3 style="color:#4c1d95;">{err['new_failures']} new failed requests detected</h3>
      <p style="color:#4c1d95;">Overall error rate: <strong>{err['error_rate']}%</strong>
         &nbsp;({err['total_failed']:,} failed / {err['total_ok'] + err['total_failed']:,} total)</p>
    </div>

    <p class="section-title">Request Counters</p>
    <div class="stat-row"><span class="stat-key">New failures (this window)</span>
      <span class="stat-val" style="color:#dc2626;">{err['new_failures']}</span></div>
    <div class="stat-row"><span class="stat-key">Total failures (lifetime)</span>
      <span class="stat-val">{err['total_failed']:,}</span></div>
    <div class="stat-row"><span class="stat-key">Total successful (lifetime)</span>
      <span class="stat-val">{err['total_ok']:,}</span></div>
    <div class="stat-row"><span class="stat-key">Error rate (lifetime)</span>
      <span class="stat-val">{err['error_rate']}%</span></div>
    <div class="stat-row"><span class="stat-key">Requests running now</span>
      <span class="stat-val">{err['running']}</span></div>
    <div class="stat-row"><span class="stat-key">Requests waiting now</span>
      <span class="stat-val">{err['waiting']}</span></div>
    <div class="stat-row"><span class="stat-key">Tokens generated (total)</span>
      <span class="stat-val">{err['tokens_gen']}</span></div>
  </div>

  <div class="card">
    <p class="section-title">GPU State</p>
    <div class="grid4">
      {metric_box("VRAM Used", gpu['vram_pct'], "%")}
      {metric_box("GPU Compute", gpu['gpu_pct'], "%")}
      {metric_box("Die Temp", gpu['temp_c'], "°C")}
      {metric_box("Power Draw", gpu['power_w'], "W")}
    </div>
  </div>

  <div class="card">
    <p class="section-title">Common Causes</p>
    <table>
      <tr><th>Cause</th><th>What It Means</th></tr>
      <tr><td>400 Bad Request</td><td>Prompt too long for current <code>--max-model-len</code>, or malformed request body from the client.</td></tr>
      <tr><td>500 Internal Error</td><td>vLLM crashed mid-generation, often an OOM or CUDA/ROCm kernel panic.</td></tr>
      <tr><td>503 / timeout</td><td>Request queue full — more concurrent users than <code>--max-num-seqs</code> allows.</td></tr>
    </table>

    <hr class="divider">
    <p class="section-title">Recommended Actions</p>
    <table>
      <tr><th>Action</th><th>Command</th></tr>
      <tr><td>Check live metrics</td><td><code>curl -s http://localhost:8000/metrics | grep vllm:request</code></td></tr>
      <tr><td>Check serve log</td><td><code>tmux attach -t vllm</code></td></tr>
      <tr><td>Restart vLLM</td><td><code>bash /workspace/scripts/29_restart_vllm_production.sh</code></td></tr>
    </table>
  </div>

  <div class="card">
    <p class="section-title">vLLM Server</p>
    <div class="stat-row"><span class="stat-key">Status</span>
      <span class="stat-val">{uptime_str}</span></div>
    <hr class="divider">
    <p class="section-title">Recent Error Lines from serve_awq.log</p>
    <pre>{err['log_lines']}</pre>
  </div>

  <div class="footer">
    Generated by Qwen-AMD monitoring &nbsp;·&nbsp;
    <a href="https://github.com/AjithThaduri/Qwen-AMD">AjithThaduri/Qwen-AMD</a>
  </div>

</div></body></html>"""


# ── send ──────────────────────────────────────────────────────────────────────

def send_email(cfg, subject, html_body):
    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = cfg["EMAIL_FROM"]
    msg["To"]      = ", ".join(cfg["EMAIL_TO"].split(","))
    msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP(cfg["EMAIL_SMTP_HOST"], int(cfg["EMAIL_SMTP_PORT"])) as s:
        s.ehlo()
        s.starttls()
        s.login(cfg["EMAIL_SMTP_USER"], cfg["EMAIL_SMTP_PASSWORD"])
        s.sendmail(cfg["EMAIL_FROM"], cfg["EMAIL_TO"].split(","), msg.as_string())

    print(f"[{datetime.now(timezone.utc):%H:%M:%S}] Email sent: {subject}")


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--daily",       action="store_true")
    group.add_argument("--alert",       action="store_true")
    group.add_argument("--error-alert", action="store_true")
    group.add_argument("--test",        action="store_true")
    args = parser.parse_args()

    cfg   = load_config()
    now   = datetime.now(timezone.utc)
    gpu   = get_gpu_stats()
    vllm  = get_vllm_status()
    disk  = get_disk_usage()

    if args.daily or args.test:
        peaks   = get_peak_stats_today()
        metrics = get_vllm_metrics()
        subject = (f"[MI300X] Daily GPU Report — {now.strftime('%b %d %Y')}"
                   if args.daily else
                   f"[MI300X] Test Email — {now.strftime('%b %d %Y %H:%M UTC')}")
        html = build_daily_html(gpu, peaks, vllm, disk, metrics, now)
        send_email(cfg, subject, html)
        if args.test:
            print("Test email sent.")

    elif args.alert:
        try:
            vram = float(gpu["vram_pct"])
        except Exception:
            vram = 0
        if vram < 85:
            print(f"VRAM at {vram}% — below threshold, no alert sent.")
            return
        reason = (f"VRAM is at {vram:.0f}%, exceeding the 85% alert threshold. "
                  f"vLLM is {'running (PID ' + str(vllm['pid']) + ')' if vllm['running'] else 'NOT running'}. "
                  f"GPU compute is at {gpu['gpu_pct']}%.")
        subject = f"[MI300X] VRAM ALERT {vram:.0f}% — {now.strftime('%b %d %H:%M UTC')}"
        html = build_alert_html(gpu, vllm, reason, now)
        send_email(cfg, subject, html)

    elif getattr(args, "error_alert"):
        err = get_error_delta()
        if err is None:
            print("Could not reach /metrics — vLLM may be down. No alert sent.")
            return
        # Alert threshold: 5+ new failures in this 5-min window
        if err["new_failures"] < 5:
            print(f"{err['new_failures']} new failures — below threshold (5), no alert sent.")
            return
        # Cooldown: max one error alert per 30 minutes
        cooldown_file = Path("/tmp/vllm_error_alert_cooldown")
        import time
        now_ts = int(time.time())
        last_sent = 0
        if cooldown_file.exists():
            try:
                last_sent = int(cooldown_file.read_text().strip())
            except Exception:
                pass
        if now_ts - last_sent < 1800:
            remaining = 1800 - (now_ts - last_sent)
            print(f"{err['new_failures']} new failures but cooldown active — {remaining}s remaining.")
            return
        cooldown_file.write_text(str(now_ts))
        subject = (f"[MI300X] ERROR ALERT — {err['new_failures']} failures "
                   f"({err['error_rate']}% rate) — {now.strftime('%b %d %H:%M UTC')}")
        html = build_error_alert_html(gpu, vllm, err, now)
        send_email(cfg, subject, html)


if __name__ == "__main__":
    main()
