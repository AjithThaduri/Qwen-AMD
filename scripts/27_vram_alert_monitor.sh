#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 27_vram_alert_monitor.sh
# Run this ON THE RUNPOD POD (in a tmux window or via cron).
# Checks VRAM every 5 minutes. Sends an alert email if > 85%.
# Cooldown: 60 minutes between alerts so you don't get spammed.
#
# Usage:
#   bash /workspace/scripts/27_vram_alert_monitor.sh          # run forever
#   bash /workspace/scripts/27_vram_alert_monitor.sh --once   # check once and exit
# ══════════════════════════════════════════════════════════════════════════════

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
ALERT_SCRIPT="${SCRIPT_DIR}/26_gpu_email_report.py"
COOLDOWN_FILE="/tmp/vram_alert_last_sent"
POLL_INTERVAL=300    # 5 minutes
COOLDOWN_SECS=3600   # 1 hour between alerts
THRESHOLD=85

ts() { date '+%H:%M:%S'; }

check_once() {
    VRAM=$(rocm-smi --showmemuse 2>/dev/null \
           | grep 'GPU Memory Allocated' \
           | awk -F: '{print $2}' | tr -d ' %')

    if [[ -z "$VRAM" || "$VRAM" == "N/A" ]]; then
        echo "[$(ts)] Could not read VRAM — skipping check."
        return
    fi

    echo "[$(ts)] VRAM: ${VRAM}%  (threshold: ${THRESHOLD}%)"

    if (( VRAM > THRESHOLD )); then
        # Cooldown: don't spam — only alert once per hour
        NOW=$(date +%s)
        LAST=0
        [[ -f "$COOLDOWN_FILE" ]] && LAST=$(cat "$COOLDOWN_FILE")
        ELAPSED=$(( NOW - LAST ))

        if (( ELAPSED >= COOLDOWN_SECS )); then
            echo "[$(ts)] VRAM ${VRAM}% > ${THRESHOLD}% — sending alert email..."
            source /workspace/vllm_rocm_env.sh 2>/dev/null
            python3 "$ALERT_SCRIPT" --alert
            echo "$NOW" > "$COOLDOWN_FILE"
            echo "[$(ts)] Alert sent. Next alert allowed in ${COOLDOWN_SECS}s."
        else
            REMAINING=$(( COOLDOWN_SECS - ELAPSED ))
            echo "[$(ts)] VRAM still high but cooldown active — ${REMAINING}s until next alert."
        fi
    fi
}

if [[ "${1:-}" == "--once" ]]; then
    check_once
    exit 0
fi

echo "[$(ts)] VRAM monitor started (poll every ${POLL_INTERVAL}s, alert threshold ${THRESHOLD}%)"
while true; do
    check_once
    sleep "$POLL_INTERVAL"
done
