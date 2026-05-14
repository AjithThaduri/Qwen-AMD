#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# 24_bench_vllm_serve.sh
# Run this ON THE RUNPOD POD.
# Sweeps `vllm bench serve` across request rates 1, 5, 10, 20.
# Requires the vLLM server to already be running (run 19_start_vllm_tmux.sh).
# Requires ShareGPT dataset (run 23_download_sharegpt.sh first).
#
# Output : /workspace/benchmarks/results/vllm_serve/<RUN_TIMESTAMP>/
#            rate_1.json  rate_5.json  rate_10.json  rate_20.json
#            bench.log
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── config ───────────────────────────────────────────────────────────────────

ENDPOINT_BASE="http://localhost:8000"
PORT=8000
MODEL="qwen3.6-35b-a3b-awq"
TOKENIZER="/workspace/models/awq"        # local path — model name is a served alias, not a HF repo
DATASET_PATH="/workspace/benchmarks/datasets/ShareGPT_V3_unfiltered_cleaned_split.json"
RATES=(1 5 10 20)
NUM_PROMPTS=200
NUM_WARMUPS=5
PERCENTILE_METRICS="ttft,tpot,itl,e2el"
METRIC_PERCENTILES="50,90,95,99"

RUN_TS=$(date '+%Y%m%d_%H%M%S')
RESULT_DIR="/workspace/benchmarks/results/vllm_serve/${RUN_TS}"
LOGFILE="${RESULT_DIR}/bench.log"

ts() { date '+%H:%M:%S'; }
log() { echo "[$(ts)] $*" | tee -a "$LOGFILE"; }

# ── setup ────────────────────────────────────────────────────────────────────

mkdir -p "$RESULT_DIR"
# Touch log early so all output goes there from the start
touch "$LOGFILE"

echo ""
echo "══════════════════════════════════════════════"
echo "  vLLM bench serve — request-rate sweep"
echo "  Model     : $MODEL"
echo "  Rates     : ${RATES[*]}"
echo "  Prompts   : $NUM_PROMPTS  (warmups: $NUM_WARMUPS)"
echo "  Result dir: $RESULT_DIR"
echo "══════════════════════════════════════════════"
echo ""

log "=== vLLM bench serve sweep started ==="
log "Model  : $MODEL"
log "Rates  : ${RATES[*]}"
log "Results: $RESULT_DIR"

# ── environment ──────────────────────────────────────────────────────────────

if [[ -f /workspace/vllm_rocm_env.sh ]]; then
    log "Sourcing /workspace/vllm_rocm_env.sh ..."
    # shellcheck disable=SC1091
    source /workspace/vllm_rocm_env.sh
else
    log "WARNING: /workspace/vllm_rocm_env.sh not found — proceeding with current environment."
fi

# ── pre-flight checks ────────────────────────────────────────────────────────

log "Checking vllm bench serve is available..."
if ! vllm bench serve --help &>/dev/null; then
    log "✗ 'vllm bench serve' not available. Check vLLM install."
    exit 1
fi

log "Checking dataset exists: $DATASET_PATH"
if [[ ! -f "$DATASET_PATH" ]]; then
    log "✗ Dataset not found: $DATASET_PATH"
    log "  Run 23_download_sharegpt.sh first."
    exit 1
fi

log "Checking vLLM server is reachable at $ENDPOINT_BASE ..."
if ! curl -sf "${ENDPOINT_BASE}/health" &>/dev/null && \
   ! curl -sf "${ENDPOINT_BASE}/v1/models" &>/dev/null; then
    log "✗ vLLM server not responding at $ENDPOINT_BASE."
    log "  Start it with: bash scripts/19_start_vllm_tmux.sh"
    exit 1
fi
log "✓ Server is up."

# ── sweep ────────────────────────────────────────────────────────────────────

declare -A P50_TTFT
declare -A P99_TTFT

for RATE in "${RATES[@]}"; do
    RESULT_FILE="${RESULT_DIR}/rate_${RATE}.json"

    log ""
    log "────────────────────────────────────────────"
    log "  Rate: ${RATE} req/s  →  ${RESULT_FILE}"
    log "────────────────────────────────────────────"

    vllm bench serve \
        --host localhost \
        --port "$PORT" \
        --endpoint /v1/chat/completions \
        --model "$MODEL" \
        --tokenizer "$TOKENIZER" \
        --dataset-name sharegpt \
        --dataset-path "$DATASET_PATH" \
        --num-prompts "$NUM_PROMPTS" \
        --num-warmups "$NUM_WARMUPS" \
        --request-rate "$RATE" \
        --percentile-metrics "$PERCENTILE_METRICS" \
        --metric-percentiles "$METRIC_PERCENTILES" \
        --save-result \
        --result-dir "$RESULT_DIR" \
        --result-filename "rate_${RATE}.json" \
        2>&1 | tee -a "$LOGFILE"

    if [[ -f "$RESULT_FILE" ]]; then
        log "✓ Saved: $RESULT_FILE"
        # Extract p50 / p99 TTFT using python (available in the vllm env)
        READ=$(python3 - <<PYEOF 2>/dev/null || echo "? ?"
import json, sys
with open("$RESULT_FILE") as f:
    d = json.load(f)
metrics = d.get("metrics", d)
p50 = metrics.get("ttft_ms_percentile_50", metrics.get("p50_ttft_ms", "?"))
p99 = metrics.get("ttft_ms_percentile_99", metrics.get("p99_ttft_ms", "?"))
print(p50, p99)
PYEOF
        )
        P50_TTFT[$RATE]=$(echo "$READ" | awk '{print $1}')
        P99_TTFT[$RATE]=$(echo "$READ" | awk '{print $2}')
        log "  TTFT p50=${P50_TTFT[$RATE]} ms   p99=${P99_TTFT[$RATE]} ms"
    else
        log "  WARNING: result file not found — bench may have failed for this rate."
        P50_TTFT[$RATE]="FAILED"
        P99_TTFT[$RATE]="FAILED"
    fi
done

# ── summary table ────────────────────────────────────────────────────────────

SUMMARY="
══════════════════════════════════════════════════════
  SUMMARY — vLLM bench serve sweep
  Model     : $MODEL
  Run       : $RUN_TS
  Prompts   : $NUM_PROMPTS  (warmups: $NUM_WARMUPS)
──────────────────────────────────────────────────────
  Rate (req/s)   TTFT p50 (ms)   TTFT p99 (ms)
──────────────────────────────────────────────────────"

for RATE in "${RATES[@]}"; do
    SUMMARY+=$(printf "\n  %-14s %-16s %s" "$RATE" "${P50_TTFT[$RATE]:-?}" "${P99_TTFT[$RATE]:-?}")
done

SUMMARY+="
──────────────────────────────────────────────────────
  Results: $RESULT_DIR
  Log    : $LOGFILE
══════════════════════════════════════════════════════
"

echo "$SUMMARY" | tee -a "$LOGFILE"
log "=== Sweep complete ==="
