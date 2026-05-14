#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 21_gpu_monitor_daily.sh
# Run this ON THE RUNPOD POD.
# Two modes:
#   --snapshot    (default) Print a one-time GPU stats snapshot to terminal.
#   --install-cron         Register a daily 9 AM cron job that appends a
#                          timestamped snapshot to /workspace/gpu_stats/daily/.
#
# Output : /workspace/gpu_stats/daily/YYYY-MM-DD.log
# Cron   : 0 9 * * * /workspace/scripts/21_gpu_monitor_daily.sh
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

STATS_DIR="/workspace/gpu_stats/daily"
SCRIPT_PATH="/workspace/scripts/21_gpu_monitor_daily.sh"
CRON_ENTRY="0 9 * * * $SCRIPT_PATH"

ts() { date '+%H:%M:%S'; }

# ── helpers ──────────────────────────────────────────────────────────────────

check_rocm_smi() {
    if ! command -v rocm-smi &>/dev/null; then
        echo "[$(ts)] ✗ rocm-smi not found. Is ROCm installed?"
        echo "         Try: ls /opt/rocm/bin/rocm-smi"
        exit 1
    fi
}

take_snapshot() {
    local logfile="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    {
        echo "=== GPU Snapshot: $timestamp ==="
        echo ""
        echo "--- General (VRAM / GPU% / Temp / Power) ---"
        rocm-smi --showmeminfo vram --showuse --showtemp --showpower 2>&1 || true
        echo ""
        echo "--- Full rocm-smi ---"
        rocm-smi 2>&1 || true
        echo ""
        echo "--- JSON (machine-readable) ---"
        rocm-smi --json 2>/dev/null || true
        echo ""
        echo "=== END ==="
        echo ""
    } | tee -a "$logfile"
}

# ── main ─────────────────────────────────────────────────────────────────────

MODE="${1:---snapshot}"

check_rocm_smi

case "$MODE" in

    --install-cron)
        echo "[$(ts)] Registering daily cron job..."
        # Add only if not already present
        if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH"; then
            echo "[$(ts)] ✓ Cron entry already present — nothing to do."
            crontab -l | grep "$SCRIPT_PATH"
        else
            (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
            echo "[$(ts)] ✓ Cron entry added:"
            echo "         $CRON_ENTRY"
        fi
        echo "[$(ts)] Current crontab:"
        crontab -l
        ;;

    --snapshot|*)
        echo ""
        echo "══════════════════════════════════════════════"
        echo "  GPU Snapshot  —  $(date '+%Y-%m-%d %H:%M:%S')"
        echo "  Logs to: $STATS_DIR"
        echo "══════════════════════════════════════════════"
        echo ""

        mkdir -p "$STATS_DIR"
        LOGFILE="$STATS_DIR/$(date '+%Y-%m-%d').log"

        echo "[$(ts)] Writing snapshot to: $LOGFILE"
        take_snapshot "$LOGFILE"
        echo "[$(ts)] ✓ Snapshot complete."
        echo "         Run with --install-cron to schedule this daily at 09:00."
        ;;
esac
