#!/usr/bin/env python3
"""
14_test_chat_stream.py
Run from your MAC after vLLM is started on the pod.

Sends a streaming chat completion request.
Prints each token as it arrives and measures time-to-first-token (TTFT).

Usage:
    python3 scripts/14_test_chat_stream.py
"""

import os
import sys
import time
from pathlib import Path

# ── Load .env ─────────────────────────────────────────────────────────────
repo_root = Path(__file__).parent.parent
env_file = repo_root / ".env"

if env_file.exists():
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip().strip('"'))

BASE_URL = os.environ.get("RUNPOD_PUBLIC_BASE_URL", "").rstrip("/")
API_KEY  = os.environ.get("VLLM_API_KEY", "dev-test-key")
MODEL    = (
    os.environ.get("SERVED_MODEL_NAME_Q4")
    or os.environ.get("SERVED_MODEL_NAME_Q5")
    or os.environ.get("SERVED_MODEL_NAME_FP8")
    or "qwen3-30b-a3b-q4"
)

if not BASE_URL:
    print("✗ RUNPOD_PUBLIC_BASE_URL is not set in .env"); sys.exit(1)

try:
    from openai import OpenAI
except ImportError:
    print("✗ openai package not installed. Run: pip3 install openai"); sys.exit(1)

print(f"\n{'═'*50}")
print(f"  Streaming chat test")
print(f"  Endpoint : {BASE_URL}/v1")
print(f"  Model    : {MODEL}")
print(f"{'═'*50}\n")

client = OpenAI(base_url=f"{BASE_URL}/v1", api_key=API_KEY)

PROMPT = "Explain what a KV cache is in large language models, in 3 sentences."
print(f"Prompt: {PROMPT}\n")
print("─" * 50)
print("Streaming response (tokens appear as received):")
print("─" * 50)

start_time = time.time()
first_token_time = None
total_chars = 0
token_count = 0

try:
    stream = client.chat.completions.create(
        model=MODEL,
        messages=[{"role": "user", "content": PROMPT}],
        max_tokens=200,
        stream=True,
    )

    for chunk in stream:
        delta = chunk.choices[0].delta
        if delta.content:
            if first_token_time is None:
                # Time from request sent to first token received
                first_token_time = time.time()
            print(delta.content, end="", flush=True)
            total_chars += len(delta.content)
            token_count += 1

except Exception as e:
    print(f"\n✗ Streaming request failed: {e}")
    sys.exit(1)

total_time = time.time() - start_time
ttft = (first_token_time - start_time) if first_token_time else None

print(f"\n{'─'*50}")
print(f"Total time       : {total_time:.2f}s")
print(f"Time to 1st token: {ttft:.3f}s" if ttft else "Time to 1st token: n/a")
print(f"Approx tokens    : {token_count}")
if total_time > 0 and token_count > 0:
    print(f"Tokens/sec       : {token_count / total_time:.1f}")
print(f"\n✓ Streaming test passed.\n")
