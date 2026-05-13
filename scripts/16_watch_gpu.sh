#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 16_watch_gpu.sh
# Run this ON THE RUNPOD POD in a separate terminal or tmux pane.
# Shows a live-updating view of GPU utilization, VRAM, power, and temperature.
# Updates every 1 second. Press Ctrl+C to exit.
# ══════════════════════════════════════════════════════════════════════════════

if ! command -v rocm-smi &>/dev/null; then
    echo "✗ rocm-smi not found. Is ROCm installed?"
    echo "  Try: ls /opt/rocm/bin/rocm-smi"
    exit 1
fi

echo "Starting live GPU monitor (Ctrl+C to stop)..."
echo ""

# watch runs the command every N seconds and refreshes the screen
# -n 1 = refresh every 1 second
# -d   = highlight values that changed between refreshes
watch -n 1 -d rocm-smi
