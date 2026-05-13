#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 04_install_vllm_rocm.sh
# Run this ON THE RUNPOD POD.
# Installs PyTorch + vLLM for AMD GPU (ROCm) — tested on MI300X.
#
# Verified stack (2025-05 on RunPod MI300X):
#   Driver:     amdgpu 6.10.5
#   ROCm (OS):  5.7.0 installed, but driver supports ROCm 6.3 userspace
#   torch:      2.9.1+rocm6.3  (PyPI wheel index rocm6.3)
#   vLLM:       0.16.0         (latest version requiring torch==2.9.1)
#   Python:     3.11
#
# Key discovery: even though /opt/rocm-5.7.0 is the only ROCm install,
# the AMDGPU kernel driver (6.10.5) supports ROCm 6.3 userspace libraries,
# so PyTorch ROCm 6.3 wheels load and GPU is visible.
#
# vLLM 0.16.0 supports:
#   - GGUF model loading (Q4_K_M, Q5_K_M, etc.)
#   - Qwen3MoeForCausalLM architecture (Qwen3.6-35B-A3B)
#   - OpenAI-compatible API server
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

ROCM_WHEEL_INDEX="https://download.pytorch.org/whl/rocm6.3"
TORCH_VERSION="2.9.1"
VLLM_VERSION="0.16.0"

echo ""
echo "══════════════════════════════════════════════"
echo "  Installing PyTorch + vLLM (ROCm / AMD GPU)"
echo "══════════════════════════════════════════════"
echo ""
echo "  Target: torch==${TORCH_VERSION}+rocm6.3  vLLM==${VLLM_VERSION}"
echo ""

# ── Step 1: Install PyTorch for ROCm 6.3 ─────────────────────────────────
echo "→ Installing PyTorch ${TORCH_VERSION}+rocm6.3..."
pip3 install \
    torch=="${TORCH_VERSION}" \
    torchvision \
    torchaudio \
    --index-url "${ROCM_WHEEL_INDEX}" \
    --force-reinstall \
    --quiet

echo ""
echo "→ Verifying PyTorch GPU access..."
python3 - <<'PYEOF'
import torch
ok = torch.cuda.is_available()
print(f"  torch: {torch.__version__}")
print(f"  GPU available: {ok}")
if ok:
    print(f"  GPU count: {torch.cuda.device_count()}")
    print(f"  GPU 0: {torch.cuda.get_device_name(0)}")
else:
    print("  ✗  GPU not visible — check driver and ROCm installation")
    raise SystemExit(1)
PYEOF

echo ""

# ── Step 2: Install vLLM ──────────────────────────────────────────────────
echo "→ Installing vLLM ${VLLM_VERSION}..."
echo "  This may take 5–15 minutes."
echo ""

pip3 install "vllm==${VLLM_VERSION}" \
    --extra-index-url "${ROCM_WHEEL_INDEX}"

echo ""

# ── Step 3: Verify installation ───────────────────────────────────────────
echo "── Verification ──────────────────────────────"
VLLM_TARGET_DEVICE=rocm python3 - <<'PYEOF'
import sys

try:
    import torch
    print(f"  ✓  PyTorch: {torch.__version__}  GPU: {torch.cuda.is_available()}")
except Exception as e:
    print(f"  ✗  PyTorch error: {e}"); sys.exit(1)

try:
    import vllm
    print(f"  ✓  vLLM: {vllm.__version__}")
except Exception as e:
    print(f"  ✗  vLLM import failed: {e}"); sys.exit(1)

# Verify GGUF support
try:
    from vllm.model_executor.model_loader.gguf_loader import GGUFModelLoader
    print("  ✓  GGUF loader: present")
except ImportError as e:
    print(f"  ✗  GGUF loader missing: {e}")

# Verify Qwen3 MoE architecture
try:
    from vllm.model_executor.models import ModelRegistry
    archs = ModelRegistry.get_supported_archs()
    qwen3moe = [a for a in archs if "Qwen3Moe" in a]
    if qwen3moe:
        print(f"  ✓  Qwen3MoE architecture: {qwen3moe[0]}")
    else:
        print("  ⚠  Qwen3MoeForCausalLM not found in ModelRegistry")
except Exception as e:
    print(f"  ⚠  ModelRegistry check failed: {e}")
PYEOF

echo ""

# ── Step 4: Confirm vLLM CLI is accessible ────────────────────────────────
echo "── vLLM CLI ──────────────────────────────────"
if command -v vllm &>/dev/null; then
    vllm --version
    echo "  ✓  'vllm' command found in PATH"
else
    echo "  ⚠  'vllm' not in PATH."
    echo "     Try: export PATH=\$PATH:\$HOME/.local/bin"
    echo "     Or:  python3 -m vllm.entrypoints.openai.api_server --help"
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  Installation complete."
echo "  Stack: torch ${TORCH_VERSION}+rocm6.3  vLLM ${VLLM_VERSION}"
echo "  Next: run 05_download_models.sh"
echo "══════════════════════════════════════════════"
echo ""
