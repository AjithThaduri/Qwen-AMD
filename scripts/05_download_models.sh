#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 05_download_models.sh
# Run this ON THE RUNPOD POD.
# Downloads Q4_K_M and Q5_K_M GGUF files from Hugging Face.
#
# Model source: bartowski/Qwen_Qwen3.6-35B-A3B-GGUF
#   Q4_K_M: ~21–23 GB (exact size depends on bartowski's build)
#   Q5_K_M: ~25–27 GB
#
# IMPORTANT: Before running, verify exact filenames at:
#   https://huggingface.co/bartowski/Qwen_Qwen3.6-35B-A3B-GGUF/tree/main
# Update GGUF_Q4_FILENAME and GGUF_Q5_FILENAME in .env if they differ.
#
# Requires: HF_TOKEN in .env
# Requires: huggingface_hub  (pip install huggingface_hub)
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Load environment ───────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$REPO_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
    # Export all variables from .env, skipping comments and blank lines
    set -a
    source "$ENV_FILE"
    set +a
    echo "  ✓  Loaded .env from $ENV_FILE"
else
    echo "  ⚠  No .env file found at $ENV_FILE"
    echo "     Copy .env.example to .env and fill in your values."
    exit 1
fi

# ── Validate required variables ────────────────────────────────────────────
: "${MODEL_DIR:?'MODEL_DIR is not set in .env'}"
: "${GGUF_HF_REPO:?'GGUF_HF_REPO is not set in .env'}"
: "${GGUF_Q4_FILENAME:?'GGUF_Q4_FILENAME is not set in .env'}"
: "${GGUF_Q5_FILENAME:?'GGUF_Q5_FILENAME is not set in .env'}"
: "${Q4_MODEL_PATH:?'Q4_MODEL_PATH is not set in .env'}"
: "${Q5_MODEL_PATH:?'Q5_MODEL_PATH is not set in .env'}"

echo ""
echo "══════════════════════════════════════════════"
echo "  Downloading GGUF model files"
echo "  Source repo : $GGUF_HF_REPO"
echo "  Destination : $MODEL_DIR"
echo "══════════════════════════════════════════════"
echo ""

# ── Live filename verification ────────────────────────────────────────────
# List available files in the repo so you can confirm the filenames before
# the actual download starts. If the filename in .env doesn't match what
# you see here, press Ctrl+C and update GGUF_Q4_FILENAME / GGUF_Q5_FILENAME.
echo "── Available files in $GGUF_HF_REPO ────────"
python3 - <<PYEOF
from huggingface_hub import list_repo_files
import os
token = os.environ.get("HF_TOKEN") or None
try:
    files = list(list_repo_files("${GGUF_HF_REPO}", repo_type="model", token=token))
    gguf_files = sorted([f for f in files if f.endswith(".gguf")])
    if gguf_files:
        for f in gguf_files:
            marker = " ← Q4 target" if "Q4_K_M" in f else (" ← Q5 target" if "Q5_K_M" in f else "")
            print(f"  {f}{marker}")
    else:
        print("  (no .gguf files found — check repo name in .env)")
except Exception as e:
    print(f"  Could not list files: {e}")
    print("  Continuing anyway — download will fail if filename is wrong.")
PYEOF
echo ""
echo "  Q4 filename in .env : $GGUF_Q4_FILENAME"
echo "  Q5 filename in .env : $GGUF_Q5_FILENAME"
echo ""
echo "  ⚠  If the filenames above do NOT match what's listed, press Ctrl+C"
echo "     and update GGUF_Q4_FILENAME / GGUF_Q5_FILENAME in .env"
echo ""
echo "  Continuing in 5 seconds..."
sleep 5

# ── Create destination directory ──────────────────────────────────────────
mkdir -p "$MODEL_DIR"
echo "  ✓  Model directory ready: $MODEL_DIR"
echo ""

# ── Authenticate with Hugging Face if token is set ────────────────────────
if [ -n "${HF_TOKEN:-}" ]; then
    echo "→ Logging into Hugging Face..."
    python3 -c "
from huggingface_hub import login
login(token='${HF_TOKEN}', add_to_git_credential=False)
print('  ✓  HF login successful')
"
else
    echo "  ⚠  HF_TOKEN not set. Proceeding without auth."
    echo "     This will fail if the repo is gated."
    echo "     Set HF_TOKEN in .env if you get a 401/403 error."
fi
echo ""

# ── Helper: download one file, skip if already present ────────────────────
download_if_missing() {
    local dest_path="$1"
    local hf_repo="$2"
    local filename="$3"

    if [ -f "$dest_path" ]; then
        local size
        size=$(du -sh "$dest_path" | cut -f1)
        echo "  ✓  Already exists: $dest_path  ($size) — skipping."
        return 0
    fi

    echo "→ Downloading $filename from $hf_repo ..."
    echo "   Destination: $dest_path"
    echo "   (This may take 10-30 min depending on network speed)"
    echo ""

    python3 - <<PYEOF
from huggingface_hub import hf_hub_download
import os, shutil

# Download to HF cache, then move to our model dir
local_path = hf_hub_download(
    repo_id="${hf_repo}",
    filename="${filename}",
    repo_type="model",
    local_dir="${MODEL_DIR}",
    local_dir_use_symlinks=False,
)
print(f"  ✓  Downloaded to: {local_path}")
PYEOF
}

# ── Download Q4_K_M ────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "  File 1/2: Q4_K_M (~21–23 GB for 35B model)"
echo "══════════════════════════════════════════════"
download_if_missing \
    "$Q4_MODEL_PATH" \
    "$GGUF_HF_REPO" \
    "$GGUF_Q4_FILENAME"
echo ""

# ── Download Q5_K_M ────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════"
echo "  File 2/2: Q5_K_M (~25–27 GB for 35B model)"
echo "══════════════════════════════════════════════"
download_if_missing \
    "$Q5_MODEL_PATH" \
    "$GGUF_HF_REPO" \
    "$GGUF_Q5_FILENAME"
echo ""

# ── Final check ───────────────────────────────────────────────────────────
echo "── Files in $MODEL_DIR ───────────────────"
ls -lh "$MODEL_DIR"
echo ""

echo "══════════════════════════════════════════════"
echo "  Download complete."
echo "  Verify the paths in .env match the files above."
echo "  Next: run 06_serve_q4_8k.sh"
echo "══════════════════════════════════════════════"
echo ""
