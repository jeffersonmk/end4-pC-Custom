#!/usr/bin/env python3
"""Download (pull) a model into the local Ollama, printing progress as JSON lines.

  ollama-pull.py MODEL [--models-dir DIR] [--size-bytes N]

  {"phase": "pull", "percent": 42, "completed": 123, "total": 456, "speed": 1000000, "status": "..."}
  {"ok": true}   or   {"ok": false, "error": "..."}

Talks to the local Ollama HTTP API only (OLLAMA_HOST honoured), so the models land in whatever
folder that server uses. --models-dir/--size-bytes only feed a free-space check before starting.
Stopping the script (SIGTERM) cancels the transfer; Ollama keeps the partial files, so pulling
the same model again resumes where it stopped.
"""
import json
import os
import re
import shutil
import sys
import time
import urllib.request

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$")


def base_url() -> str:
    host = os.environ.get("OLLAMA_HOST", "").strip() or "127.0.0.1:11434"
    if "://" not in host:
        host = "http://" + host
    host = host.replace("//:", "//127.0.0.1:").replace("//0.0.0.0", "//127.0.0.1")
    return host.rstrip("/")


def emit(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def free_bytes(path: str) -> int:
    probe = path
    while probe and not os.path.exists(probe):
        probe = os.path.dirname(probe)
    return shutil.disk_usage(probe or "/").free


def main() -> None:
    args = sys.argv[1:]
    if not args or not NAME_RE.match(args[0]):
        return emit({"ok": False, "error": "invalid-name"})
    model = args[0]

    def opt(name, default=""):
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default

    models_dir = opt("--models-dir")
    expected = int(float(opt("--size-bytes", "0") or 0))
    if models_dir and expected:
        free = free_bytes(models_dir)
        if free < expected * 1.05:
            return emit({"ok": False, "error": "no-space", "needed": expected, "free": free})

    req = urllib.request.Request(
        base_url() + "/api/pull",
        data=json.dumps({"model": model, "stream": True}).encode(),
        headers={"Content-Type": "application/json"})
    layers = {}  # digest -> [completed, total]
    started = time.time()
    last_emit = 0.0
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if ev.get("error"):
                    return emit({"ok": False, "error": str(ev["error"])})
                digest = ev.get("digest")
                if digest and ev.get("total"):
                    layers[digest] = [ev.get("completed") or 0, ev["total"]]
                done = sum(c for c, _t in layers.values())
                seen = sum(t for _c, t in layers.values())
                total = max(seen, expected)
                now = time.time()
                if now - last_emit >= 0.4 and total > 0:
                    last_emit = now
                    emit({"phase": "pull", "percent": min(99, int(done * 100 / total)),
                          "completed": done, "total": total,
                          "speed": int(done / max(now - started, 0.1)),
                          "status": ev.get("status", "")})
                if ev.get("status") == "success":
                    return emit({"ok": True})
    except Exception as e:
        return emit({"ok": False, "error": f"connection: {e}"})
    emit({"ok": False, "error": "interrupted"})


if __name__ == "__main__":
    main()
