#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 05_download_awq.sh
# Run this ON THE RUNPOD POD.
# Downloads the INT4 AWQ model from HuggingFace.
#
# Model : QuantTrio/Qwen3.6-35B-A3B-AWQ  (~24.5 GB)
# Format: HuggingFace safetensors (NOT GGUF)
# vLLM  : Load directly by HF model ID — no local path needed
#
# Requires: HF_TOKEN in .env
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

if [ -f "$REPO_ROOT/.env" ]; then
    set -a; source "$REPO_ROOT/.env"; set +a
    echo "  ✓  Loaded .env"
else
    echo "  ✗  .env not found — aborting."; exit 1
fi

: "${AWQ_MODEL_ID:?'AWQ_MODEL_ID not set in .env'}"
: "${AWQ_MODEL_DIR:?'AWQ_MODEL_DIR not set in .env'}"
: "${HF_TOKEN:?'HF_TOKEN not set in .env — set it before running this script'}"

echo ""
echo "══════════════════════════════════════════════"
echo "  Downloading INT4 AWQ model"
echo "  Source : $AWQ_MODEL_ID"
echo "  Dest   : $AWQ_MODEL_DIR"
echo "  Size   : ~24.5 GB"
echo "══════════════════════════════════════════════"
echo ""

if [ -d "$AWQ_MODEL_DIR" ] && [ "$(ls -A "$AWQ_MODEL_DIR" 2>/dev/null)" ]; then
    echo "  ✓  Model directory already exists and is non-empty:"
    ls -lh "$AWQ_MODEL_DIR"
    echo ""
    echo "  If you want to re-download, delete $AWQ_MODEL_DIR first."
    echo "  Skipping download."
    exit 0
fi

mkdir -p "$AWQ_MODEL_DIR"

echo "→ Logging into Hugging Face..."
python3 -c "
from huggingface_hub import login
login(token='${HF_TOKEN}', add_to_git_credential=False)
print('  ✓  HF login OK')
"

echo ""
echo "→ Downloading model files (this may take 15–30 min)..."
echo ""

python3 - <<PYEOF
from huggingface_hub import snapshot_download
import os

local_path = snapshot_download(
    repo_id="${AWQ_MODEL_ID}",
    local_dir="${AWQ_MODEL_DIR}",
    local_dir_use_symlinks=False,
    token="${HF_TOKEN}",
    ignore_patterns=["*.pt", "original/*"],
)
print(f"  ✓  Downloaded to: {local_path}")

# Show what was downloaded
import os
total = 0
for f in os.listdir(local_path):
    fp = os.path.join(local_path, f)
    if os.path.isfile(fp):
        sz = os.path.getsize(fp)
        total += sz
        print(f"    {f}  ({sz/1e9:.1f} GB)" if sz > 1e8 else f"    {f}")
print(f"\n  Total: {total/1e9:.1f} GB")
PYEOF

echo ""
echo "══════════════════════════════════════════════"
echo "  Download complete: $AWQ_MODEL_DIR"
echo "  Next: run 06_serve_awq_8k.sh"
echo "══════════════════════════════════════════════"
echo ""
