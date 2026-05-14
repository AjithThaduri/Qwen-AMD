#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 23_download_sharegpt.sh
# Run this ON THE RUNPOD POD.
# Downloads ShareGPT_V3_unfiltered_cleaned_split.json from HuggingFace.
# Skips download if the file already exists.
# Checks available disk space before downloading (~300 MB needed).
#
# Output : /workspace/benchmarks/datasets/ShareGPT_V3_unfiltered_cleaned_split.json
# Log    : /workspace/benchmarks/datasets/download.log
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

DATASET_DIR="/workspace/benchmarks/datasets"
FILENAME="ShareGPT_V3_unfiltered_cleaned_split.json"
DEST="$DATASET_DIR/$FILENAME"
LOGFILE="$DATASET_DIR/download.log"
HF_URL="https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/$FILENAME"
MIN_FREE_MB=500   # Require at least 500 MB free before downloading

ts() { date '+%H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOGFILE"; }

mkdir -p "$DATASET_DIR"

# Write log header for this run
echo "" >> "$LOGFILE"
echo "=== Download run: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOGFILE"

echo ""
echo "══════════════════════════════════════════════"
echo "  ShareGPT Dataset Downloader"
echo "  Dest  : $DEST"
echo "  Source: $HF_URL"
echo "══════════════════════════════════════════════"
echo ""

# ── already present? ─────────────────────────────────────────────────────────

if [[ -f "$DEST" ]]; then
    SIZE=$(du -sh "$DEST" | cut -f1)
    log "✓ File already exists ($SIZE) — skipping download."
    log "  $DEST"
    echo ""
    echo "  To re-download, delete the file first:"
    echo "    rm $DEST"
    exit 0
fi

# ── disk space check ─────────────────────────────────────────────────────────

FREE_MB=$(df -m "$DATASET_DIR" | awk 'NR==2 {print $4}')
log "Free disk space in $DATASET_DIR: ${FREE_MB} MB"

if (( FREE_MB < MIN_FREE_MB )); then
    log "✗ Not enough disk space. Need ${MIN_FREE_MB} MB free, have ${FREE_MB} MB."
    log "  Free up space and retry."
    exit 1
fi

# ── download ─────────────────────────────────────────────────────────────────

log "Checking wget..."
if ! command -v wget &>/dev/null; then
    log "wget not found — installing..."
    apt-get install -y wget 2>&1 | tee -a "$LOGFILE" || {
        log "✗ Could not install wget. Install it manually and retry."
        exit 1
    }
fi

log "Starting download (~280–350 MB)..."
log "URL: $HF_URL"

wget \
    --progress=bar:force:noscroll \
    --tries=3 \
    --timeout=120 \
    --output-document="$DEST" \
    --append-output="$LOGFILE" \
    "$HF_URL"

# ── verify ───────────────────────────────────────────────────────────────────

if [[ ! -f "$DEST" ]]; then
    log "✗ Download failed — file not found at $DEST."
    exit 1
fi

FILE_SIZE=$(du -sh "$DEST" | cut -f1)
FILE_BYTES=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null || echo "?")

log "✓ Download complete."
log "  File  : $DEST"
log "  Size  : $FILE_SIZE  ($FILE_BYTES bytes)"

echo ""
echo "══════════════════════════════════════════════"
echo "  Download complete: $DEST  ($FILE_SIZE)"
echo "  Next: run 24_bench_vllm_serve.sh"
echo "══════════════════════════════════════════════"
echo ""
