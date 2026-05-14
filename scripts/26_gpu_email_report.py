#!/usr/bin/env python3
"""
26_gpu_email_report.py
Run this ON THE RUNPOD POD.

Sends a daily HTML GPU report and/or a VRAM alert email.

Modes:
  python3 26_gpu_email_report.py --daily       # Send daily report (called by cron)
  python3 26_gpu_email_report.py --alert        # Send VRAM alert (called by monitor)
  python3 26_gpu_email_report.py --test         # Send test email to verify SMTP works

Config file: /workspace/configs/email.conf  (never committed to git)
"""

import argparse
import json
import os
import smtplib
import subprocess
import sys
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path

# ── config ────────────────────────────────────────────────────────────────────

CONFIG_PATH = Path("/workspace/configs/email.conf")

# ── helpers ───────────────────────────────────────────────────────────────────

def load_config():
    if not CONFIG_PATH.exists():
        print(f"ERROR: Config not found at {CONFIG_PATH}")
        print("Run setup first: bash /workspace/scripts/26_setup_email_config.sh")
        sys.exit(1)
    cfg = {}
    for line in CONFIG_PATH.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip()
    return cfg


def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, text=True).strip()
    except Exception:
        return "N/A"


def get_gpu_stats():
    """Returns dict of GPU metrics from rocm-smi."""
    stats = {}

    # VRAM used / total
    vram_used = run("rocm-smi --showmemuse 2>/dev/null | grep 'GPU Memory Allocated' | awk -F: '{print $2}' | tr -d ' %'")
    stats["vram_pct"] = vram_used if vram_used != "N/A" else "?"

    # Temperature
    temp = run("rocm-smi --showtemp 2>/dev/null | grep 'Temperature (Sensor edge)' | awk -F: '{print $2}' | tr -d ' c'")
    stats["temp_c"] = temp if temp != "N/A" else "?"

    # GPU utilisation
    gpu_use = run("rocm-smi --showuse 2>/dev/null | grep 'GPU use' | awk -F: '{print $2}' | tr -d ' %'")
    stats["gpu_pct"] = gpu_use if gpu_use != "N/A" else "?"

    # Power draw
    power = run("rocm-smi --showpower 2>/dev/null | grep 'Average Graphics Package' | awk -F: '{print $2}' | tr -d ' W'")
    stats["power_w"] = power if power != "N/A" else "?"

    # Full rocm-smi table for email body
    stats["raw"] = run("rocm-smi 2>/dev/null")

    return stats


def get_vllm_status():
    pid = run("pgrep -f 'vllm serve' | head -1")
    if pid and pid != "N/A":
        uptime = run(f"ps -o etime= -p {pid} 2>/dev/null").strip()
        return {"running": True, "pid": pid, "uptime": uptime}
    return {"running": False, "pid": None, "uptime": None}


def get_disk_usage():
    workspace = run("df -h /workspace 2>/dev/null | tail -1 | awk '{print $2, $3, $4, $5}'")
    root = run("df -h / 2>/dev/null | tail -1 | awk '{print $2, $3, $4, $5}'")
    return {"workspace": workspace, "root": root}


def get_recent_serve_log():
    log = Path("/workspace/serve_awq.log")
    if not log.exists():
        return "Log not found."
    lines = log.read_text().splitlines()
    return "\n".join(lines[-20:])


# ── HTML builders ─────────────────────────────────────────────────────────────

STYLE = """
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         background: #f4f6f9; margin: 0; padding: 20px; color: #1a1a2e; }
  .wrapper { max-width: 680px; margin: 0 auto; }
  .header { background: linear-gradient(135deg, #e84040 0%, #c0392b 100%);
            border-radius: 12px 12px 0 0; padding: 28px 32px; color: white; }
  .header h1 { margin: 0 0 4px; font-size: 22px; font-weight: 700; }
  .header p  { margin: 0; font-size: 13px; opacity: 0.85; }
  .card { background: white; border-radius: 0; padding: 24px 32px;
          border-bottom: 1px solid #eef0f4; }
  .card:last-child { border-radius: 0 0 12px 12px; border-bottom: none; }
  .card h2 { margin: 0 0 16px; font-size: 14px; font-weight: 600;
             text-transform: uppercase; letter-spacing: 0.05em; color: #7f8c8d; }
  table { width: 100%; border-collapse: collapse; font-size: 14px; }
  th { background: #f8f9fa; padding: 10px 14px; text-align: left;
       font-weight: 600; color: #555; border-bottom: 2px solid #eee; }
  td { padding: 10px 14px; border-bottom: 1px solid #f0f0f0; color: #333; }
  tr:last-child td { border-bottom: none; }
  .badge { display: inline-block; padding: 3px 10px; border-radius: 20px;
           font-size: 12px; font-weight: 600; }
  .badge-ok  { background: #e8f5e9; color: #2e7d32; }
  .badge-warn { background: #fff3e0; color: #e65100; }
  .badge-crit { background: #ffebee; color: #c62828; }
  .badge-down { background: #f5f5f5; color: #757575; }
  .metric-big { font-size: 28px; font-weight: 700; color: #2c3e50; }
  .metric-label { font-size: 12px; color: #999; margin-top: 2px; }
  .metrics-row { display: flex; gap: 16px; flex-wrap: wrap; }
  .metric-box { flex: 1; min-width: 120px; background: #f8f9fa;
                border-radius: 8px; padding: 16px; text-align: center; }
  .alert-banner { background: #fff3cd; border: 1px solid #ffc107;
                  border-radius: 8px; padding: 16px; margin-bottom: 8px; }
  .alert-banner.critical { background: #f8d7da; border-color: #dc3545; }
  pre { background: #1e1e2e; color: #cdd6f4; border-radius: 8px;
        padding: 16px; font-size: 12px; overflow-x: auto;
        white-space: pre-wrap; word-break: break-all; }
  .footer { text-align: center; padding: 16px; font-size: 12px; color: #aaa; }
</style>
"""


def vram_badge(pct_str):
    try:
        pct = float(pct_str)
        if pct >= 90:
            return f'<span class="badge badge-crit">{pct}% CRITICAL</span>'
        elif pct >= 85:
            return f'<span class="badge badge-warn">{pct}% WARNING</span>'
        else:
            return f'<span class="badge badge-ok">{pct}% OK</span>'
    except Exception:
        return f'<span class="badge badge-down">{pct_str}</span>'


def build_daily_html(gpu, vllm, disk, now):
    vllm_badge = ('<span class="badge badge-ok">Running</span>' if vllm["running"]
                  else '<span class="badge badge-down">Stopped</span>')

    metrics_row = f"""
    <div class="metrics-row">
      <div class="metric-box">
        <div class="metric-big">{gpu['vram_pct']}%</div>
        <div class="metric-label">VRAM Used</div>
      </div>
      <div class="metric-box">
        <div class="metric-big">{gpu['gpu_pct']}%</div>
        <div class="metric-label">GPU Utilisation</div>
      </div>
      <div class="metric-box">
        <div class="metric-big">{gpu['temp_c']}°C</div>
        <div class="metric-label">Die Temperature</div>
      </div>
      <div class="metric-box">
        <div class="metric-big">{gpu['power_w']}W</div>
        <div class="metric-label">Power Draw</div>
      </div>
    </div>
    """

    uptime_str = f"PID {vllm['pid']} · Uptime {vllm['uptime']}" if vllm["running"] else "Not running"

    return f"""<!DOCTYPE html><html><head><meta charset="utf-8">{STYLE}</head><body>
<div class="wrapper">
  <div class="header">
    <h1>AMD MI300X · Daily GPU Report</h1>
    <p>{now.strftime('%A, %B %d %Y · %H:%M UTC')} &nbsp;|&nbsp; Pod: mv4dfc2mn9l8zc &nbsp;|&nbsp; Model: qwen3.6-35b-a3b-awq</p>
  </div>

  <div class="card">
    <h2>GPU Health</h2>
    {metrics_row}
    <br>
    <table>
      <tr><th>Metric</th><th>Value</th><th>Status</th></tr>
      <tr><td>VRAM Utilisation</td><td>{gpu['vram_pct']}%</td><td>{vram_badge(gpu['vram_pct'])}</td></tr>
      <tr><td>GPU Compute</td><td>{gpu['gpu_pct']}%</td><td><span class="badge badge-ok">&nbsp;</span></td></tr>
      <tr><td>Die Temperature</td><td>{gpu['temp_c']} °C</td><td><span class="badge badge-ok">&nbsp;</span></td></tr>
      <tr><td>Power Draw</td><td>{gpu['power_w']} W &nbsp;<small>(cap: 750 W)</small></td><td><span class="badge badge-ok">&nbsp;</span></td></tr>
    </table>
  </div>

  <div class="card">
    <h2>vLLM Server</h2>
    <table>
      <tr><th>Item</th><th>Value</th></tr>
      <tr><td>Status</td><td>{vllm_badge}</td></tr>
      <tr><td>Details</td><td>{uptime_str}</td></tr>
      <tr><td>Endpoint</td><td>https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Disk Usage</h2>
    <table>
      <tr><th>Mount</th><th>Size</th><th>Used</th><th>Free</th><th>Use%</th></tr>
      <tr><td>/workspace</td>
          {"".join(f"<td>{v}</td>" for v in disk['workspace'].split())}
      </tr>
      <tr><td>/ (root overlay)</td>
          {"".join(f"<td>{v}</td>" for v in disk['root'].split())}
      </tr>
    </table>
  </div>

  <div class="card">
    <h2>rocm-smi Output</h2>
    <pre>{gpu['raw']}</pre>
  </div>

  <div class="footer">
    Generated by Qwen-AMD monitoring · <a href="https://github.com/AjithThaduri/Qwen-AMD">AjithThaduri/Qwen-AMD</a>
  </div>
</div>
</body></html>"""


def build_alert_html(gpu, vllm, reason, now):
    return f"""<!DOCTYPE html><html><head><meta charset="utf-8">{STYLE}</head><body>
<div class="wrapper">
  <div class="header" style="background: linear-gradient(135deg, #c0392b 0%, #922b21 100%);">
    <h1>⚠ VRAM Alert — AMD MI300X</h1>
    <p>{now.strftime('%A, %B %d %Y · %H:%M UTC')} &nbsp;|&nbsp; Pod: mv4dfc2mn9l8zc</p>
  </div>

  <div class="card">
    <div class="alert-banner critical">
      <strong>VRAM usage exceeded 85% threshold</strong><br>
      Current usage: <strong>{gpu['vram_pct']}%</strong> &nbsp;·&nbsp; Threshold: 85%
    </div>
    <h2>What This Means</h2>
    <table>
      <tr><th>Item</th><th>Value</th><th>Note</th></tr>
      <tr><td>VRAM Used</td><td>{gpu['vram_pct']}%</td>
          <td>vLLM is configured at <code>--gpu-memory-utilization 0.85</code>.
              Usage above this may indicate KV cache pressure under heavy load.</td></tr>
      <tr><td>GPU Compute</td><td>{gpu['gpu_pct']}%</td><td>Active inference load</td></tr>
      <tr><td>Temperature</td><td>{gpu['temp_c']} °C</td><td>Normal range: &lt;90°C</td></tr>
      <tr><td>Power</td><td>{gpu['power_w']} W</td><td>Cap: 750 W</td></tr>
    </table>
  </div>

  <div class="card">
    <h2>Why It Happened</h2>
    <p>{reason}</p>
    <ul>
      <li><strong>KV cache growth:</strong> Long conversations or many concurrent requests fill the KV cache.</li>
      <li><strong>Concurrent load spike:</strong> More simultaneous users than the KV cache can hold.</li>
      <li><strong>Model weights + KV cache:</strong> Model uses ~24 GB; remaining ~138 GB is KV cache. Under 50+ concurrent users this fills fast.</li>
    </ul>
    <p><strong>Recommended actions:</strong></p>
    <ul>
      <li>Check active requests: <code>curl http://localhost:8000/metrics</code></li>
      <li>If OOM risk is high, restart vLLM: <code>tmux attach -t vllm</code> → Ctrl+C → re-run serve command</li>
      <li>Consider reducing <code>--max-model-len</code> to free KV cache space</li>
    </ul>
  </div>

  <div class="card">
    <h2>vLLM Server Status</h2>
    <p>{"Running — PID " + str(vllm["pid"]) + ", uptime " + str(vllm["uptime"]) if vllm["running"] else "NOT RUNNING"}</p>
    <h2>rocm-smi</h2>
    <pre>{gpu['raw']}</pre>
  </div>

  <div class="footer">
    Generated by Qwen-AMD monitoring · <a href="https://github.com/AjithThaduri/Qwen-AMD">AjithThaduri/Qwen-AMD</a>
  </div>
</div>
</body></html>"""


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

    print(f"[{datetime.utcnow():%H:%M:%S}] Email sent: {subject}")


# ── main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--daily",  action="store_true", help="Send daily report")
    group.add_argument("--alert",  action="store_true", help="Send VRAM alert")
    group.add_argument("--test",   action="store_true", help="Send test email")
    args = parser.parse_args()

    cfg  = load_config()
    now  = datetime.utcnow()
    gpu  = get_gpu_stats()
    vllm = get_vllm_status()
    disk = get_disk_usage()

    if args.daily:
        subject = f"[MI300X] Daily GPU Report — {now.strftime('%b %d %Y')}"
        html    = build_daily_html(gpu, vllm, disk, now)
        send_email(cfg, subject, html)

    elif args.alert:
        try:
            vram = float(gpu["vram_pct"])
        except Exception:
            vram = 0
        if vram < 85:
            print(f"VRAM at {vram}% — below threshold, no alert sent.")
            return
        reason = (f"VRAM is at {vram}%, which exceeds the 85% alert threshold. "
                  f"The vLLM server is {'running' if vllm['running'] else 'NOT running'}. "
                  f"GPU compute is at {gpu['gpu_pct']}%.")
        subject = f"[MI300X] VRAM ALERT {vram}% — {now.strftime('%b %d %Y %H:%M UTC')}"
        html    = build_alert_html(gpu, vllm, reason, now)
        send_email(cfg, subject, html)

    elif args.test:
        subject = f"[MI300X] Test Email — {now.strftime('%b %d %Y %H:%M UTC')}"
        html    = build_daily_html(gpu, vllm, disk, now)
        send_email(cfg, subject, html)
        print("Test email sent successfully.")


if __name__ == "__main__":
    main()
