#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 02_check_gpu.sh
# Run this ON THE RUNPOD POD (not your Mac).
# Verifies that ROCm can see the MI300X and prints key system info.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

echo ""
echo "══════════════════════════════════════════════"
echo "  GPU and ROCm environment check"
echo "══════════════════════════════════════════════"
echo ""

# ── 1. OS version ──────────────────────────────────────────────────────────
echo "── OS ────────────────────────────────────────"
cat /etc/os-release | grep -E "^(NAME|VERSION)="
echo ""

# ── 2. ROCm installation ───────────────────────────────────────────────────
echo "── ROCm version ──────────────────────────────"
if [ -f /opt/rocm/.info/version ]; then
    cat /opt/rocm/.info/version
elif command -v rocminfo &>/dev/null; then
    rocminfo | grep -i "ROCm Runtime Version" || echo "(rocminfo found; version not parsed)"
else
    echo "⚠  ROCm not found at /opt/rocm — install it in 03_install_base.sh"
fi
echo ""

# ── 3. rocm-smi summary ────────────────────────────────────────────────────
echo "── rocm-smi ──────────────────────────────────"
if command -v rocm-smi &>/dev/null; then
    rocm-smi
else
    echo "⚠  rocm-smi not found. ROCm may not be installed yet."
fi
echo ""

# ── 4. GPU device list via rocminfo ───────────────────────────────────────
echo "── GPU device list ───────────────────────────"
if command -v rocminfo &>/dev/null; then
    rocminfo | grep -E "Name:|Marketing Name:" | head -20
else
    echo "⚠  rocminfo not found."
fi
echo ""

# ── 5. HIP visible devices ────────────────────────────────────────────────
echo "── HIP_VISIBLE_DEVICES ───────────────────────"
echo "${HIP_VISIBLE_DEVICES:-'(not set — all GPUs visible)'}"
echo ""

# ── 6. Python + PyTorch ROCm check ────────────────────────────────────────
echo "── Python / PyTorch ──────────────────────────"
if command -v python3 &>/dev/null; then
    python3 - <<'EOF'
import sys
print(f"Python: {sys.version}")

try:
    import torch
    print(f"PyTorch: {torch.__version__}")
    print(f"ROCm available (torch.cuda.is_available): {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"GPU count: {torch.cuda.device_count()}")
        for i in range(torch.cuda.device_count()):
            props = torch.cuda.get_device_properties(i)
            total_gb = props.total_memory / (1024**3)
            print(f"  GPU {i}: {props.name}  VRAM: {total_gb:.1f} GiB")
    else:
        print("  ⚠  PyTorch cannot see a GPU. ROCm may need reinstalling.")
except ImportError:
    print("PyTorch: not installed yet — will be installed in 03/04 scripts.")
EOF
else
    echo "⚠  python3 not found."
fi
echo ""

# ── 7. Available disk space ────────────────────────────────────────────────
echo "── Disk space ────────────────────────────────"
df -h /workspace 2>/dev/null || df -h /
echo ""

echo "══════════════════════════════════════════════"
echo "  Check complete. Review any ⚠ warnings above."
echo "  Next: run 03_install_base.sh"
echo "══════════════════════════════════════════════"
echo ""
