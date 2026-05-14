#!/usr/bin/env bash
# Full load test matrix against RunPod vLLM (client-side only).
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

VENV="$REPO/.venv"
if [[ ! -x "$VENV/bin/python3" ]]; then
  echo "Creating venv at $VENV ..."
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q --upgrade openai aiohttp pandas
PY="$VENV/bin/python3"

BASE_URL="https://mv4dfc2mn9l8zc-8000.proxy.runpod.net/v1"
API_KEY="dev-test-key"
MODEL="qwen3.6-35b-a3b-awq"
PROMPTS="$REPO/results/loadtests/prompts"

RUN_DIR="$REPO/results/loadtests/run_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RUN_DIR/raw" "$RUN_DIR/summaries" "$RUN_DIR/reports"

echo "══════════════════════════════════════════════════════════════"
echo "  Load test matrix"
echo "  RUN_DIR=$RUN_DIR"
echo "══════════════════════════════════════════════════════════════"

run_case() {
  local label="$1"
  local prompt_name="$2"
  local conc="$3"
  local reqs="$4"
  local maxtok="$5"
  local use_stream="$6"

  echo ""
  echo ">>> [$label] prompt=$prompt_name concurrency=$conc requests=$reqs max_tokens=$maxtok stream=$use_stream"
  local pf="$PROMPTS/$prompt_name"
  local -a args=(
    "$REPO/scripts/benchmark_openai_load.py"
    --base-url "$BASE_URL"
    --api-key "$API_KEY"
    --model "$MODEL"
    --concurrency "$conc"
    --requests "$reqs"
    --max-tokens "$maxtok"
    --temperature 0
    --prompt-file "$pf"
    --output-raw "$RUN_DIR/raw/${label}.jsonl"
    --output-summary "$RUN_DIR/summaries/${label}.json"
    --timeout 900
    --label "$label"
  )
  if [[ "$use_stream" == "yes" ]]; then
    args+=(--stream)
  else
    args+=(--no-stream)
  fi

  "$PY" "${args[@]}" || echo "WARN: benchmark exited non-zero for $label"
  echo "    (pause 10s)"
  sleep 10
}

# SMOKE
run_case "T01_smoke_short_stream" "short_prompt.txt" 1 1 100 yes
run_case "T02_smoke_medium_stream" "medium_prompt.txt" 1 3 256 yes

# CORE CONCURRENCY
run_case "T03_medium_c5_r20_s256" "medium_prompt.txt" 5 20 256 yes
run_case "T04_medium_c10_r30_s256" "medium_prompt.txt" 10 30 256 yes
run_case "T05_medium_c20_r40_s256" "medium_prompt.txt" 20 40 256 yes
run_case "T06_medium_c50_r50_s256" "medium_prompt.txt" 50 50 256 yes

# HEAVY OUTPUT
run_case "T07_large_c10_r20_s512" "large_prompt.txt" 10 20 512 yes
run_case "T08_large_c20_r20_s512" "large_prompt.txt" 20 20 512 yes
run_case "T09_large_c50_r50_s512" "large_prompt.txt" 50 50 512 yes

# REASONING-LIKE
run_case "T10_reasoning_c10_r20_s768" "reasoning_prompt.txt" 10 20 768 yes
run_case "T11_reasoning_c20_r20_s768" "reasoning_prompt.txt" 20 20 768 yes

# CODING
run_case "T12_coding_c5_r10_s1024" "coding_prompt.txt" 5 10 1024 yes
run_case "T13_coding_c10_r20_s1024" "coding_prompt.txt" 10 20 1024 yes

# NON-STREAMING
run_case "T14_medium_c10_r20_s256_nostream" "medium_prompt.txt" 10 20 256 no
run_case "T15_large_c10_r20_s512_nostream" "large_prompt.txt" 10 20 512 no

echo ""
echo ">>> Generating reports..."
"$PY" "$REPO/scripts/generate_loadtest_report.py" "$RUN_DIR"

echo ""
echo "LOADTEST_MATRIX_COMPLETE"
echo "RUN_DIR=$RUN_DIR"
echo "REPORT=$RUN_DIR/reports/loadtest_report.md"
echo "CSV=$RUN_DIR/reports/loadtest_summary.csv"
