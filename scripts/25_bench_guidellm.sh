#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 25_bench_guidellm.sh
# Run this ON THE RUNPOD POD.
# Installs GuideLLM (if not already installed) then runs a saturation sweep
# at request rates 5, 10, 20.
# Errors are handled gracefully — a failed install or run prints clear
# instructions and exits cleanly (no set -e / no crash).
#
# Output : /workspace/benchmarks/results/guidellm/<RUN_TIMESTAMP>/
#            rate_5.txt  rate_10.txt  rate_20.txt
#            guidellm.log
# ══════════════════════════════════════════════════════════════════════════════

# NOTE: intentionally no set -e so that failures are caught and reported cleanly

TARGET="http://localhost:8000/v1"
MODEL="qwen3.6-35b-a3b-awq"
DATA_TYPE="sharegpt"
RATES=(5 10 20)

RUN_TS=$(date '+%Y%m%d_%H%M%S')
RESULT_DIR="/workspace/benchmarks/results/guidellm/${RUN_TS}"
LOGFILE="${RESULT_DIR}/guidellm.log"

ts() { date '+%H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOGFILE"; }

mkdir -p "$RESULT_DIR"
touch "$LOGFILE"

echo ""
echo "══════════════════════════════════════════════"
echo "  GuideLLM Saturation Sweep"
echo "  Target    : $TARGET"
echo "  Model     : $MODEL"
echo "  Rates     : ${RATES[*]}"
echo "  Result dir: $RESULT_DIR"
echo "══════════════════════════════════════════════"
echo ""

log "=== GuideLLM sweep started ==="

# ── environment ──────────────────────────────────────────────────────────────

if [[ -f /workspace/vllm_rocm_env.sh ]]; then
    log "Sourcing /workspace/vllm_rocm_env.sh ..."
    # shellcheck disable=SC1091
    source /workspace/vllm_rocm_env.sh 2>>"$LOGFILE" || {
        log "WARNING: vllm_rocm_env.sh sourcing reported errors (continuing)."
    }
else
    log "WARNING: /workspace/vllm_rocm_env.sh not found — using current environment."
fi

# ── install guidellm ─────────────────────────────────────────────────────────

GUIDELLM_OK=0

if command -v guidellm &>/dev/null; then
    log "✓ guidellm already installed: $(guidellm --version 2>/dev/null || echo '(version unknown)')"
    GUIDELLM_OK=1
else
    log "guidellm not found — installing via pip..."
    if pip install guidellm 2>&1 | tee -a "$LOGFILE"; then
        log "pip install succeeded. Verifying..."
        if guidellm --help &>/dev/null; then
            log "✓ guidellm installed and verified."
            GUIDELLM_OK=1
        else
            log "✗ pip install appeared to succeed but 'guidellm --help' failed."
        fi
    else
        log "✗ pip install guidellm failed."
    fi
fi

if [[ "$GUIDELLM_OK" -ne 1 ]]; then
    echo ""
    echo "══════════════════════════════════════════════"
    echo "  GuideLLM install FAILED — manual steps:"
    echo ""
    echo "  1. Activate the vllm-rocm conda env:"
    echo "       source /workspace/vllm_rocm_env.sh"
    echo "       conda activate vllm-rocm"
    echo ""
    echo "  2. Install guidellm:"
    echo "       pip install guidellm"
    echo ""
    echo "  3. Verify:"
    echo "       guidellm --help"
    echo ""
    echo "  4. Re-run this script."
    echo "══════════════════════════════════════════════"
    echo ""
    log "Exiting due to guidellm install failure."
    exit 1
fi

# ── server check ─────────────────────────────────────────────────────────────

log "Checking vLLM server at http://localhost:8000 ..."
if ! curl -sf "http://localhost:8000/health" &>/dev/null && \
   ! curl -sf "http://localhost:8000/v1/models" &>/dev/null; then
    echo ""
    echo "══════════════════════════════════════════════"
    echo "  vLLM server not responding at localhost:8000"
    echo "  Start it with: bash scripts/19_start_vllm_tmux.sh"
    echo "  Then re-run this script."
    echo "══════════════════════════════════════════════"
    log "✗ Server not reachable — exiting."
    exit 1
fi
log "✓ Server is up."

# ── sweep ────────────────────────────────────────────────────────────────────

FAILED_RATES=()

for RATE in "${RATES[@]}"; do
    RESULT_FILE="${RESULT_DIR}/rate_${RATE}.txt"

    log ""
    log "────────────────────────────────────────────"
    log "  Rate: ${RATE} req/s  →  ${RESULT_FILE}"
    log "────────────────────────────────────────────"

    {
        guidellm \
            --target "$TARGET" \
            --model "$MODEL" \
            --data-type "$DATA_TYPE" \
            --rate "$RATE" \
            --output-format text
    } 2>&1 | tee -a "$LOGFILE" > "$RESULT_FILE"
    EXIT_CODE=${PIPESTATUS[0]}

    if [[ "$EXIT_CODE" -eq 0 ]]; then
        SIZE=$(du -sh "$RESULT_FILE" | cut -f1)
        log "✓ Rate ${RATE} complete — $RESULT_FILE ($SIZE)"
    else
        log "✗ guidellm exited with code $EXIT_CODE for rate ${RATE}."
        log "  Partial output (if any) saved to: $RESULT_FILE"
        FAILED_RATES+=("$RATE")
    fi
done

# ── summary ──────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════"
echo "  GuideLLM sweep complete"
echo "  Run       : $RUN_TS"
echo "  Target    : $TARGET"
echo "  Model     : $MODEL"
echo "  Results   : $RESULT_DIR"

if [[ "${#FAILED_RATES[@]}" -gt 0 ]]; then
    echo "  FAILED rates: ${FAILED_RATES[*]}"
    echo ""
    echo "  To retry a failed rate manually:"
    echo "    guidellm --target \"$TARGET\" \\"
    echo "             --model \"$MODEL\" \\"
    echo "             --data-type \"$DATA_TYPE\" \\"
    echo "             --rate <RATE> \\"
    echo "             --output-format text"
else
    echo "  All rates completed successfully."
fi

echo "  Log       : $LOGFILE"
echo "══════════════════════════════════════════════"
echo ""

log "=== GuideLLM sweep finished ==="

if [[ "${#FAILED_RATES[@]}" -gt 0 ]]; then
    exit 1
fi
exit 0
