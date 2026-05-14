#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 22_gpu_monitor_live.sh
# Run this ON THE RUNPOD POD in a second tmux window alongside a benchmark.
# Polls rocm-smi every 3 seconds, prints a clean table, and logs timestamped
# rows to /workspace/gpu_stats/live/SESSION_TIMESTAMP.log.
#
# Usage:
#   bash scripts/22_gpu_monitor_live.sh
#   bash scripts/22_gpu_monitor_live.sh --duration 300
#
# Output : /workspace/gpu_stats/live/<TIMESTAMP>.log
# Stop   : Ctrl+C  (or --duration N seconds)
# ══════════════════════════════════════════════════════════════════════════════

LIVE_DIR="/workspace/gpu_stats/live"
POLL_INTERVAL=3
DURATION=0   # 0 = run until Ctrl+C

ts() { date '+%H:%M:%S'; }

# ── arg parsing ──────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --duration)
            DURATION="${2:?'--duration requires a value (seconds)'}"
            shift 2
            ;;
        *)
            echo "Unknown arg: $1"
            echo "Usage: $0 [--duration SECONDS]"
            exit 1
            ;;
    esac
done

# ── checks ───────────────────────────────────────────────────────────────────

if ! command -v rocm-smi &>/dev/null; then
    echo "[$(ts)] ✗ rocm-smi not found. Is ROCm installed?"
    exit 1
fi

# ── setup ────────────────────────────────────────────────────────────────────

mkdir -p "$LIVE_DIR"
SESSION_TS=$(date '+%Y%m%d_%H%M%S')
LOGFILE="$LIVE_DIR/${SESSION_TS}.log"

echo ""
echo "══════════════════════════════════════════════"
echo "  Live GPU Monitor"
echo "  Poll interval : ${POLL_INTERVAL}s"
if [[ "$DURATION" -gt 0 ]]; then
    echo "  Duration      : ${DURATION}s"
else
    echo "  Duration      : until Ctrl+C"
fi
echo "  Log file      : $LOGFILE"
echo "══════════════════════════════════════════════"
echo ""

# Write log header
{
    echo "# Live GPU log — session started $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Fields: timestamp | gpu_id | vram_used_mb | vram_total_mb | vram_pct | gpu_use_pct | temp_c | power_w"
    echo ""
} > "$LOGFILE"

# Column header for terminal
printf "%-10s  %-6s  %-14s  %-12s  %-10s  %-6s  %-8s\n" \
    "TIME" "GPU" "VRAM_USED(MB)" "VRAM_TOT(MB)" "VRAM%" "USE%" "TEMP_C"
printf '%s\n' "----------  ------  --------------  ------------  ----------  ------  --------"

# ── cleanup on exit ──────────────────────────────────────────────────────────

trap 'echo ""; echo "[$(ts)] Stopped. Log: $LOGFILE"; exit 0' INT TERM

# ── poll loop ────────────────────────────────────────────────────────────────

START_TIME=$(date +%s)

while true; do
    NOW=$(date +%s)
    if [[ "$DURATION" -gt 0 ]] && (( NOW - START_TIME >= DURATION )); then
        echo ""
        echo "[$(ts)] Duration reached (${DURATION}s). Done."
        break
    fi

    TIMESTAMP=$(date '+%H:%M:%S')
    FULL_TS=$(date '+%Y-%m-%d %H:%M:%S')

    # Append raw rocm-smi snapshot to log
    echo "=== $FULL_TS ===" >> "$LOGFILE"
    rocm-smi >> "$LOGFILE" 2>&1 || true

    # Parse per-GPU values for the live table
    # rocm-smi --showmeminfo vram --showuse --showtemp --showpower
    # produces labelled lines; we extract numerics with awk
    PARSED=$(rocm-smi --showmeminfo vram --showuse --showtemp --showpower 2>/dev/null | \
        awk '
        /GPU\[/ { gpu=substr($1,5,length($1)-5) }
        /VRAM Total Memory/ { vram_total=$NF }
        /VRAM Total Used Memory/ { vram_used=$NF }
        /GPU use/ { use=$NF }
        /Temperature.*junction|Temperature.*edge/ && !temp { temp=$NF }
        /Average Graphics Package Power/ { power=$NF }
        /^$/ && gpu!="" {
            vram_pct = (vram_total>0) ? int(vram_used/vram_total*100) : "?"
            printf "%s %s %s %s %s %s\n", gpu, vram_used, vram_total, vram_pct, use, temp
            gpu=""; vram_total=0; vram_used=0; use="?"; temp=""; power="?"
        }
        ' 2>/dev/null || true)

    if [[ -z "$PARSED" ]]; then
        printf "[%s]  (no parse — see log)\n" "$TIMESTAMP"
    else
        while IFS=' ' read -r gpu vram_used vram_total vram_pct use temp; do
            printf "%-10s  %-6s  %-14s  %-12s  %-10s  %-6s  %-8s\n" \
                "$TIMESTAMP" "$gpu" "$vram_used" "$vram_total" "${vram_pct}%" "${use}%" "$temp"
            # Structured log row
            echo "${FULL_TS} | ${gpu} | ${vram_used} | ${vram_total} | ${vram_pct} | ${use} | ${temp}" >> "$LOGFILE"
        done <<< "$PARSED"
    fi

    echo "" >> "$LOGFILE"
    sleep "$POLL_INTERVAL"
done

echo "[$(ts)] Log saved to: $LOGFILE"
