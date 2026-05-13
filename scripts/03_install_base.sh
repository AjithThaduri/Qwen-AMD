#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 03_install_base.sh
# Run this ON THE RUNPOD POD (not your Mac).
# Installs system packages needed before vLLM: Python, pip, tmux, and
# confirms ROCm is functional.
#
# SAFE to re-run — apt-get and pip are idempotent.
# Does NOT wipe, reset, or modify ROCm itself.
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

echo ""
echo "══════════════════════════════════════════════"
echo "  Installing base system packages"
echo "══════════════════════════════════════════════"
echo ""

# ── 1. Update package list ─────────────────────────────────────────────────
echo "→ Updating apt package list..."
apt-get update -qq

# ── 2. Install essentials ──────────────────────────────────────────────────
echo "→ Installing: tmux, curl, wget, git, jq, build-essential..."
apt-get install -y --no-install-recommends \
    tmux \
    curl \
    wget \
    git \
    jq \
    build-essential \
    libssl-dev \
    ca-certificates \
    python3-pip \
    python3-venv \
    python3-dev \
    lsof

echo ""

# ── 3. Upgrade pip ────────────────────────────────────────────────────────
echo "→ Upgrading pip..."
python3 -m pip install --upgrade pip

# ── 4. Install huggingface-hub CLI (needed by 05_download_models.sh) ──────
echo "→ Installing huggingface_hub..."
pip3 install --upgrade huggingface_hub

# ── 5. Confirm ROCm is visible ────────────────────────────────────────────
echo ""
echo "── ROCm sanity check ─────────────────────────"
if command -v rocm-smi &>/dev/null; then
    rocm-smi --showproductname 2>/dev/null || rocm-smi
    echo "  ✓  rocm-smi found"
else
    echo "  ⚠  rocm-smi not found."
    echo "     ROCm should already be on the RunPod MI300X image."
    echo "     If missing, check: ls /opt/rocm/bin/"
    echo "     And add to PATH: export PATH=\$PATH:/opt/rocm/bin"
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  Base packages installed."
echo "  Next: run 04_install_vllm_rocm.sh"
echo "══════════════════════════════════════════════"
echo ""
