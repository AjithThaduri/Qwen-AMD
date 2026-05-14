#!/usr/bin/env python3
"""
30_api_gateway.py — FastAPI gateway in front of vLLM (port 8000)
Run this ON THE RUNPOD POD.  Listens on port 8080.

Features:
  • 3 named API keys: dev, production, spare
  • Per-key usage tracking  → /workspace/gateway_stats/usage.json
  • Priority concurrency: heavy requests (>HEAVY_THRESHOLD tokens) get a
    separate, smaller concurrency pool so light requests are never blocked
  • Strips <think>…</think> from all responses (streaming + non-streaming)
  • Disables Qwen3 thinking via chat_template_kwargs at the API level
  • Proxies: POST /v1/chat/completions
             POST /v1/completions
             GET  /v1/models
             GET  /health
             GET  /v1/usage   (per-key stats, requires any valid key)

Start:  bash /workspace/scripts/31_start_gateway.sh
Logs:   /workspace/gateway_stats/gateway.log
"""

import asyncio
import json
import logging
import re
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx
import uvicorn
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse

# ── config ────────────────────────────────────────────────────────────────────

VLLM_BASE     = "http://localhost:8001"  # vLLM on internal port 8001
VLLM_INT_KEY  = "dev-test-key"          # internal vLLM key (never exposed)
GATEWAY_PORT  = 8000                    # gateway takes the public port

# Public-facing API keys  (share only these with clients)
API_KEYS = {
    "sk-qwen-dev-xK9mP2nL":   "dev",
    "sk-qwen-prod-rT5jW8vQ":  "prod",
    "sk-qwen-spare-hN3cA6yD": "spare",
}

# Concurrency limits
LIGHT_THRESHOLD = 1500   # tokens — requests below this are "light"
LIGHT_LIMIT     = 85     # max simultaneous light requests
HEAVY_LIMIT     = 15     # max simultaneous heavy requests (subset of total 100)

# Usage stats file
STATS_DIR  = Path("/workspace/gateway_stats")
STATS_FILE = STATS_DIR / "usage.json"

# ── logging ───────────────────────────────────────────────────────────────────

STATS_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    filename=str(STATS_DIR / "gateway.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("gateway")

# ── state ─────────────────────────────────────────────────────────────────────

_light_sem: asyncio.Semaphore
_heavy_sem: asyncio.Semaphore
_stats_lock: asyncio.Lock
_http: httpx.AsyncClient


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _light_sem, _heavy_sem, _stats_lock, _http
    _light_sem  = asyncio.Semaphore(LIGHT_LIMIT)
    _heavy_sem  = asyncio.Semaphore(HEAVY_LIMIT)
    _stats_lock = asyncio.Lock()
    _http = httpx.AsyncClient(base_url=VLLM_BASE, timeout=300.0)
    _init_stats()
    log.info("Gateway started on port %d", GATEWAY_PORT)
    yield
    await _http.aclose()


app = FastAPI(title="Qwen3 Gateway", lifespan=lifespan)

# ── usage stats ───────────────────────────────────────────────────────────────

def _init_stats():
    if STATS_FILE.exists():
        return
    data = {
        name: {"requests": 0, "input_tokens": 0, "output_tokens": 0,
               "errors": 0, "last_used": None}
        for name in set(API_KEYS.values())
    }
    STATS_FILE.write_text(json.dumps(data, indent=2))


def _load_stats() -> dict:
    try:
        return json.loads(STATS_FILE.read_text())
    except Exception:
        return {}


async def _record(key_name: str, input_tok: int, output_tok: int, error: bool):
    async with _stats_lock:
        data = _load_stats()
        if key_name not in data:
            data[key_name] = {"requests": 0, "input_tokens": 0,
                               "output_tokens": 0, "errors": 0, "last_used": None}
        data[key_name]["requests"]     += 1
        data[key_name]["input_tokens"] += input_tok
        data[key_name]["output_tokens"]+= output_tok
        if error:
            data[key_name]["errors"]   += 1
        data[key_name]["last_used"] = datetime.now(timezone.utc).isoformat()
        STATS_FILE.write_text(json.dumps(data, indent=2))


# ── auth ──────────────────────────────────────────────────────────────────────

def _auth(authorization: Optional[str]) -> str:
    """Validate Bearer token. Returns key_name (dev/prod/spare)."""
    if not authorization:
        raise HTTPException(401, "Missing Authorization header")
    parts = authorization.strip().split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(401, "Authorization header must be: Bearer <key>")
    key = parts[1]
    if key not in API_KEYS:
        raise HTTPException(401, "Invalid API key")
    return API_KEYS[key]


# ── token estimation ──────────────────────────────────────────────────────────

def _estimate_input_tokens(body: dict) -> int:
    """Rough token estimate from request body (chars ÷ 4)."""
    try:
        if "messages" in body:
            text = " ".join(
                m.get("content", "") for m in body["messages"]
                if isinstance(m.get("content"), str)
            )
        else:
            text = str(body.get("prompt", ""))
        return max(1, len(text) // 4)
    except Exception:
        return 1


# ── think-tag stripping ───────────────────────────────────────────────────────

_THINK_RE = re.compile(r"<think>.*?</think>", re.DOTALL)


def _strip_think(text: str) -> str:
    return _THINK_RE.sub("", text).lstrip("\n")


class _StreamThinkStripper:
    """Stateful stripper for SSE streams that handles tags split across chunks."""

    def __init__(self):
        self._state  = "normal"   # normal | in_think
        self._buf    = ""

    def feed(self, chunk: str) -> str:
        out = []
        i = 0
        while i < len(chunk):
            if self._state == "normal":
                tag_start = chunk.find("<think>", i)
                if tag_start == -1:
                    # No opening tag — emit everything
                    out.append(chunk[i:])
                    break
                # Emit up to the tag, then switch state
                out.append(chunk[i:tag_start])
                i = tag_start + len("<think>")
                self._state = "in_think"
            else:  # in_think
                tag_end = chunk.find("</think>", i)
                if tag_end == -1:
                    # Haven't seen closing tag yet — buffer, emit nothing
                    self._buf += chunk[i:]
                    break
                # Found closing tag — discard buffered content, resume normal
                self._buf = ""
                i = tag_end + len("</think>")
                self._state = "normal"
        return "".join(out)


# ── request forwarding ────────────────────────────────────────────────────────

def _inject_no_think(body: dict) -> dict:
    """Ask Qwen3 not to output thinking tags."""
    if "messages" in body:
        body.setdefault("chat_template_kwargs", {})["enable_thinking"] = False
    return body


async def _forward_non_streaming(
    path: str, body: dict, input_tok: int, key_name: str
) -> JSONResponse:
    try:
        resp = await _http.post(
            path,
            json=body,
            headers={"Authorization": f"Bearer {VLLM_INT_KEY}",
                     "Content-Type": "application/json"},
        )
        data = resp.json()

        # Strip think tags from content
        if "choices" in data:
            for choice in data["choices"]:
                msg = choice.get("message", {})
                if "content" in msg and msg["content"]:
                    msg["content"] = _strip_think(msg["content"])
                txt = choice.get("text")
                if txt:
                    choice["text"] = _strip_think(txt)

        output_tok = data.get("usage", {}).get("completion_tokens", 0)
        await _record(key_name, input_tok, output_tok, resp.status_code >= 400)
        log.info("[%s] %s %d in=%d out=%d", key_name, path, resp.status_code,
                 input_tok, output_tok)
        return JSONResponse(content=data, status_code=resp.status_code)

    except Exception as exc:
        await _record(key_name, input_tok, 0, True)
        log.error("[%s] upstream error: %s", key_name, exc)
        raise HTTPException(502, f"Upstream error: {exc}")


async def _forward_streaming(
    path: str, body: dict, input_tok: int, key_name: str
) -> StreamingResponse:
    """Stream SSE from vLLM, stripping think tags on the fly."""

    # Ask vLLM to include usage in the final chunk
    body.setdefault("stream_options", {})["include_usage"] = True

    stripper    = _StreamThinkStripper()
    output_toks = [0]
    error_flag  = [False]

    async def generate():
        try:
            async with _http.stream(
                "POST", path,
                json=body,
                headers={"Authorization": f"Bearer {VLLM_INT_KEY}",
                         "Content-Type": "application/json"},
            ) as r:
                error_flag[0] = r.status_code >= 400
                async for line in r.aiter_lines():
                    if not line.startswith("data:"):
                        if line:
                            yield line + "\n\n"
                        continue

                    payload = line[5:].strip()
                    if payload == "[DONE]":
                        yield "data: [DONE]\n\n"
                        break

                    try:
                        chunk = json.loads(payload)
                    except json.JSONDecodeError:
                        yield line + "\n\n"
                        continue

                    # Capture usage from final chunk
                    if chunk.get("usage"):
                        output_toks[0] = chunk["usage"].get("completion_tokens", 0)

                    # Strip think tags from delta content
                    for choice in chunk.get("choices", []):
                        delta = choice.get("delta", {})
                        if delta.get("content"):
                            delta["content"] = stripper.feed(delta["content"])
                        txt = choice.get("text")
                        if txt:
                            choice["text"] = stripper.feed(txt)

                    yield f"data: {json.dumps(chunk)}\n\n"
        except Exception as exc:
            error_flag[0] = True
            log.error("[%s] stream error: %s", key_name, exc)
            yield f'data: {{"error": "{exc}"}}\n\n'
        finally:
            asyncio.create_task(
                _record(key_name, input_tok, output_toks[0], error_flag[0])
            )
            log.info("[%s] stream %s in=%d out=%d err=%s",
                     key_name, path, input_tok, output_toks[0], error_flag[0])

    return StreamingResponse(generate(), media_type="text/event-stream")


async def _dispatch(path: str, request: Request, key_name: str):
    body = await request.json()
    body = _inject_no_think(body)
    input_tok = _estimate_input_tokens(body)
    is_heavy  = input_tok > LIGHT_THRESHOLD
    streaming = body.get("stream", False)

    sem = _heavy_sem if is_heavy else _light_sem
    async with sem:
        if streaming:
            return await _forward_streaming(path, body, input_tok, key_name)
        return await _forward_non_streaming(path, body, input_tok, key_name)


# ── routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    try:
        r = await _http.get("/health")
        return {"status": "ok", "vllm": r.status_code == 200}
    except Exception:
        return JSONResponse({"status": "degraded", "vllm": False}, status_code=503)


@app.get("/v1/models")
async def models(authorization: Optional[str] = Header(None)):
    _auth(authorization)
    r = await _http.get("/v1/models",
                        headers={"Authorization": f"Bearer {VLLM_INT_KEY}"})
    return JSONResponse(r.json())


@app.post("/v1/chat/completions")
async def chat_completions(request: Request,
                           authorization: Optional[str] = Header(None)):
    key_name = _auth(authorization)
    return await _dispatch("/v1/chat/completions", request, key_name)


@app.post("/v1/completions")
async def completions(request: Request,
                      authorization: Optional[str] = Header(None)):
    key_name = _auth(authorization)
    return await _dispatch("/v1/completions", request, key_name)


@app.get("/v1/usage")
async def usage(authorization: Optional[str] = Header(None)):
    """Per-key usage stats. Requires any valid API key."""
    _auth(authorization)
    data  = _load_stats()
    total = {"requests": 0, "input_tokens": 0, "output_tokens": 0, "errors": 0}
    for v in data.values():
        for k in total:
            total[k] += v.get(k, 0)
    return {"keys": data, "total": total,
            "as_of": datetime.now(timezone.utc).isoformat()}


# ── main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    uvicorn.run(
        "30_api_gateway:app",
        host="0.0.0.0",
        port=GATEWAY_PORT,
        log_level="warning",
        access_log=False,
    )
