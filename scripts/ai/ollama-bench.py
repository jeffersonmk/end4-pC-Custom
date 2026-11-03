#!/usr/bin/env python3
"""Measure how fast an installed Ollama model really runs on this PC.

  ollama-bench.py run MODEL [--ctx N]   generate ~160 tokens, print JSON progress lines, save the result
  ollama-bench.py list                  one JSON line with every saved result

Results live in ~/.local/state/quickshell/user/ai/ollama-bench.json and feed the model catalog:
a measured speed replaces the estimate, and the measurements calibrate the estimate of the models
you haven't tried yet. A model that was not loaded before the test is unloaded again afterwards.

Talks to the local Ollama HTTP API only (OLLAMA_HOST honoured). Stdlib only. Always exits 0.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "quickshell", "user", "ai", "ollama-bench.json")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$")
PROMPT = ("Write a detailed, imaginative short story about a robot who learns to paint, "
          "with several paragraphs.")
TOKENS = 160


def base_url() -> str:
    host = os.environ.get("OLLAMA_HOST", "").strip() or "127.0.0.1:11434"
    if "://" not in host:
        host = "http://" + host
    host = host.replace("//:", "//127.0.0.1:").replace("//0.0.0.0", "//127.0.0.1")
    return host.rstrip("/")


def call(path, payload=None, timeout=30.0):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(base_url() + path, data=data,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or "{}")


def emit(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def load_results() -> dict:
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_result(name: str, result: dict) -> None:
    data = load_results()
    data[name] = result
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, STATE)


def loaded_models() -> dict:
    try:
        return {m.get("name"): m for m in call("/api/ps", timeout=4).get("models") or []}
    except Exception:
        return {}


def run(name: str, ctx: int) -> None:
    if not NAME_RE.match(name):
        return emit({"ok": False, "error": "invalid-name"})
    try:
        show = call("/api/show", {"model": name}, timeout=8)
    except urllib.error.HTTPError as e:
        return emit({"ok": False, "error": "not-installed" if e.code == 404 else f"http-{e.code}"})
    except Exception:
        return emit({"ok": False, "error": "ollama-not-running"})
    if "embedding" in (show.get("capabilities") or []):
        return emit({"ok": False, "error": "not-chat"})

    was_loaded = name in loaded_models()
    emit({"phase": "running", "wasLoaded": was_loaded})
    started = time.time()
    try:
        r = call("/api/generate", {
            "model": name, "prompt": PROMPT, "stream": False, "keep_alive": "5m",
            "options": {"num_predict": TOKENS, "num_ctx": ctx, "temperature": 0},
        }, timeout=300)
    except Exception as e:
        return emit({"ok": False, "error": f"generate-failed: {e}"})

    eval_count = r.get("eval_count") or 0
    eval_ns = r.get("eval_duration") or 0
    if eval_count < 8 or eval_ns <= 0:
        return emit({"ok": False, "error": "no-tokens"})
    prompt_ns = r.get("prompt_eval_duration") or 0
    ps = loaded_models().get(name) or {}
    size, vram = ps.get("size") or 0, ps.get("size_vram") or 0
    result = {
        "tps": round(eval_count / (eval_ns / 1e9), 1),
        "promptTps": round((r.get("prompt_eval_count") or 0) / (prompt_ns / 1e9), 1) if prompt_ns else 0,
        "gpuPercent": round(100 * vram / size) if size else 0,
        "vramBytes": vram,
        "ctx": ctx,
        "tokens": eval_count,
        "loadSeconds": round((r.get("load_duration") or 0) / 1e9, 1),
        "at": int(started),
    }
    save_result(name, result)
    if not was_loaded:
        try:
            call("/api/generate", {"model": name, "keep_alive": 0}, timeout=15)
        except Exception:
            pass
    emit({"ok": True, "result": result})


def main() -> None:
    args = sys.argv[1:]
    cmd = args[0] if args else "list"
    if cmd == "list":
        emit({"results": load_results()})
    elif cmd == "run" and len(args) > 1:
        ctx = int(args[args.index("--ctx") + 1]) if "--ctx" in args else 4096
        run(args[1], ctx)
    else:
        emit({"ok": False, "error": "usage: ollama-bench.py run MODEL [--ctx N] | list"})


if __name__ == "__main__":
    main()
