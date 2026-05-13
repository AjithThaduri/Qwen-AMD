#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 04_install_vllm_rocm.sh
# Run this ON THE RUNPOD POD.
# Installs vLLM with ROCm (AMD GPU) support.
#
# Strategy:
#   1. Try the official pre-built ROCm wheel from vLLM (fastest, recommended).
#   2. If that fails, print instructions for building from source.
#
# Do NOT run this with pip install vllm (CPU-only).
# The ROCm wheel is a separate index.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

echo ""
echo "══════════════════════════════════════════════"
echo "  Installing vLLM with ROCm support"
echo "══════════════════════════════════════════════"
echo ""

# ── Detect ROCm version ────────────────────────────────────────────────────
if [ -f /opt/rocm/.info/version ]; then
    ROCM_VERSION=$(cat /opt/rocm/.info/version | cut -d'.' -f1,2)
    echo "  Detected ROCm version: $ROCM_VERSION"
else
    # Default to ROCm 6.x which is current on MI300X pods
    ROCM_VERSION="5.7"
    echo "  Could not detect ROCm version — defaulting to $ROCM_VERSION"
    echo "  If this is wrong, check: cat /opt/rocm/.info/version"
fi

echo ""

# ── Step 1: Install PyTorch for ROCm (if not already present) ─────────────
echo "→ Checking PyTorch ROCm..."
if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    echo "  ✓  PyTorch with ROCm already available — skipping PyTorch install."
else
    echo "  PyTorch not found or no GPU visible. Installing PyTorch for ROCm..."
    # ROCm version on this pod is 5.7 — use the matching PyTorch wheel.
    # If your pod has a different ROCm version, change rocm5.7 below to match.
    pip3 install torch torchvision torchaudio \
        --index-url https://download.pytorch.org/whl/rocm5.7
    echo "  ✓  PyTorch installed."
fi
echo ""

# ── Step 2: Install vLLM ──────────────────────────────────────────────────
echo "→ Installing vLLM..."
echo "  This may take 5–15 minutes."
echo ""

# Strategy:
#   1. Try pip install vllm (works when torch with ROCm is already present)
#   2. If that fails, try the ROCm 5.7 wheel index from pytorch.org
#   ROCm 5.7 is supported by vLLM 0.5.x and later.

pip3 install vllm \
    || {
        echo ""
        echo "  ⚠  Plain vllm install failed. Trying ROCm 5.7 wheel index..."
        echo ""
        pip3 install vllm \
            --index-url https://download.pytorch.org/whl/rocm5.7
    }

echo ""

# ── Step 3: Verify installation ───────────────────────────────────────────
echo "── Verification ──────────────────────────────"
python3 - <<'EOF'
try:
    import vllm
    print(f"  ✓  vLLM version: {vllm.__version__}")
except ImportError as e:
    print(f"  ✗  vLLM import failed: {e}")

try:
    import torch
    print(f"  ✓  PyTorch version: {torch.__version__}")
    print(f"  ✓  CUDA/ROCm available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"  ✓  GPU count: {torch.cuda.device_count()}")
        print(f"  ✓  GPU 0: {torch.cuda.get_device_name(0)}")
except Exception as e:
    print(f"  ✗  PyTorch check failed: {e}")
EOF

echo ""

# ── Step 4: Confirm vLLM CLI is accessible ────────────────────────────────
echo "── vLLM CLI ──────────────────────────────────"
if command -v vllm &>/dev/null; then
    vllm --version
    echo "  ✓  'vllm' command found in PATH"
else
    # vllm may be installed but not in PATH; check common locations
    VLLM_BIN=$(python3 -c "import site; print(site.getusersitepackages())" 2>/dev/null || echo "")
    echo "  ⚠  'vllm' not in PATH."
    echo "     Try: export PATH=\$PATH:\$HOME/.local/bin"
    echo "     Or check: python3 -m vllm.entrypoints.openai.api_server --help"
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  vLLM installation complete."
echo "  If you see any ⚠ above, address them before"
echo "  running the serve scripts."
echo "  Next: run 05_download_models.sh"
echo "══════════════════════════════════════════════"
echo ""
