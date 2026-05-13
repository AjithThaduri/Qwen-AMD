#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 17_collect_gpu_metrics.sh
# Run this ON THE RUNPOD POD during a benchmark run.
# Appends timestamped rocm-smi snapshots to a log file at a chosen interval.
# Ctrl+C to stop.
#
# Usage:
#   bash scripts/17_collect_gpu_metrics.sh /workspace/repo/results/gpu_run1.log 5
#   (arg 1 = output file, arg 2 = interval in seconds, defaults: /tmp/gpu.log, 5)
# ══════════════════════════════════════════════════════════════════════════════

OUTPUT_FILE="${1:-/tmp/gpu_metrics.log}"
INTERVAL="${2:-5}"

if ! command -v rocm-smi &>/dev/null; then
    echo "✗ rocm-smi not found."
    exit 1
fi

# Create parent directory if it doesn't exist
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "══════════════════════════════════════════════"
echo "  GPU metrics collection started"
echo "  Output  : $OUTPUT_FILE"
echo "  Interval: every ${INTERVAL}s"
echo "  Stop    : Ctrl+C"
echo "══════════════════════════════════════════════"
echo ""

# Write header to log
echo "# GPU metrics log — started $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Trap Ctrl+C to print a clean exit message
trap 'echo ""; echo "Stopped. Log saved to: $OUTPUT_FILE"; exit 0' INT

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Write a timestamped separator
    echo "=== $TIMESTAMP ===" >> "$OUTPUT_FILE"

    # Append full rocm-smi output
    rocm-smi >> "$OUTPUT_FILE" 2>&1

    # Also capture JSON metrics for easier parsing
    echo "--- JSON ---" >> "$OUTPUT_FILE"
    rocm-smi --json 2>/dev/null >> "$OUTPUT_FILE" || true

    echo "" >> "$OUTPUT_FILE"

    # Print a one-line progress indicator to the terminal
    VRAM=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Used" | awk '{print $NF}' | head -1)
    printf "\r  [%s]  VRAM used: %s MB" "$TIMESTAMP" "${VRAM:-?}"

    sleep "$INTERVAL"
done
