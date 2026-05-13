#!/usr/bin/env python3
"""
13_test_chat_non_stream.py
Run from your MAC after vLLM is started on the pod.

Sends a single non-streaming chat completion request and prints the response.
Uses the OpenAI Python SDK pointed at your RunPod vLLM endpoint.

Usage:
    python3 scripts/13_test_chat_non_stream.py

Environment variables (from .env):
    RUNPOD_PUBLIC_BASE_URL  — e.g. https://mv4dfc2mn9l8zc-8000.proxy.runpod.net
    VLLM_API_KEY            — the --api-key you passed to vllm serve
    SERVED_MODEL_NAME_Q4    — name you passed to --served-model-name
"""

import os
import sys
import time
from pathlib import Path

# ── Load .env from repo root ───────────────────────────────────────────────
repo_root = Path(__file__).parent.parent
env_file = repo_root / ".env"

if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip().strip('"'))
    print("  ✓  Loaded .env")
else:
    print("  ⚠  No .env found — reading from system environment.")

# ── Read config ────────────────────────────────────────────────────────────
BASE_URL = os.environ.get("RUNPOD_PUBLIC_BASE_URL", "").rstrip("/")
API_KEY  = os.environ.get("VLLM_API_KEY", "dev-test-key")
# Use the first served model name that is set, in order of preference
MODEL    = (
    os.environ.get("SERVED_MODEL_NAME_Q4")
    or os.environ.get("SERVED_MODEL_NAME_Q5")
    or os.environ.get("SERVED_MODEL_NAME_FP8")
    or "qwen3-30b-a3b-q4"
)

if not BASE_URL:
    print("✗ RUNPOD_PUBLIC_BASE_URL is not set in .env")
    sys.exit(1)

print(f"\n{'═'*50}")
print(f"  Non-streaming chat test")
print(f"  Endpoint : {BASE_URL}/v1")
print(f"  Model    : {MODEL}")
print(f"{'═'*50}\n")

# ── Import OpenAI SDK ──────────────────────────────────────────────────────
try:
    from openai import OpenAI
except ImportError:
    print("✗ openai package not installed. Run: pip3 install openai")
    sys.exit(1)

client = OpenAI(
    base_url=f"{BASE_URL}/v1",
    api_key=API_KEY,
)

# ── Send request ───────────────────────────────────────────────────────────
PROMPT = "Say hello in one sentence and tell me what model you are."
print(f"Prompt: {PROMPT}\n")

start = time.time()

try:
    response = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": PROMPT}],
        max_tokens=100,
        stream=False,
    )
except Exception as e:
    print(f"✗ Request failed: {e}")
    sys.exit(1)

elapsed = time.time() - start

# ── Print result ───────────────────────────────────────────────────────────
content = response.choices[0].message.content
usage   = response.usage

print(f"{'─'*50}")
print(f"Response:\n{content}")
print(f"{'─'*50}")
print(f"Latency        : {elapsed:.2f}s")
print(f"Prompt tokens  : {usage.prompt_tokens if usage else 'n/a'}")
print(f"Completion tok : {usage.completion_tokens if usage else 'n/a'}")
print(f"Total tokens   : {usage.total_tokens if usage else 'n/a'}")
print(f"\n✓ Non-streaming test passed.\n")
