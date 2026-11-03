#!/usr/bin/env python3
"""Installed Ollama models with details, for the Intelligence model picker.

  ollama-models.py list            one JSON line: {"running", "version", "models": [...]}
  ollama-models.py unload NAME     free the model from VRAM/RAM now
  ollama-models.py delete NAME     remove the model from disk

Talks to the local Ollama HTTP API only (OLLAMA_HOST is honoured, default
127.0.0.1:11434). Stdlib only, no credentials, never leaves the machine unless
OLLAMA_HOST points elsewhere. Always prints one JSON object and exits 0, so the
caller never has to parse stderr.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.request

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$")


def base_url() -> str:
    host = os.environ.get("OLLAMA_HOST", "").strip() or "127.0.0.1:11434"
    if "://" not in host:
        host = "http://" + host
    # ":11434" or "0.0.0.0:11434" are valid server binds, not valid client targets
    host = host.replace("//:", "//127.0.0.1:").replace("//0.0.0.0", "//127.0.0.1")
    return host.rstrip("/")


def call(path: str, payload=None, method=None, timeout=4.0):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(base_url() + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read().decode() or "{}"
    return json.loads(body)


def context_length(show: dict):
    for key, value in (show.get("model_info") or {}).items():
        if key.endswith(".context_length") and isinstance(value, int):
            return value
    return None


def list_models() -> dict:
    try:
        tags = call("/api/tags")
    except Exception:
        return {"running": False, "version": None, "models": []}

    try:
        version = call("/api/version").get("version")
    except Exception:
        version = None

    loaded = {}
    try:
        for m in call("/api/ps").get("models") or []:
            loaded[m.get("name") or m.get("model")] = m
    except Exception:
        pass

    models = []
    for m in tags.get("models") or []:
        name = m.get("name") or m.get("model")
        if not name:
            continue
        details = m.get("details") or {}
        info = {
            "name": name,
            "size": m.get("size") or 0,
            "family": details.get("family") or "",
            "parameterSize": details.get("parameter_size") or "",
            "quantization": details.get("quantization_level") or "",
            "modifiedAt": m.get("modified_at") or "",
            "capabilities": [],
            "capabilitiesKnown": False,  # old Ollama versions don't report them
            "contextLength": None,
            "loaded": False,
            "sizeVram": 0,
        }
        try:
            show = call("/api/show", {"model": name}, timeout=6.0)
            info["capabilitiesKnown"] = "capabilities" in show
            info["capabilities"] = [c for c in show.get("capabilities") or [] if c != "completion"]
            info["contextLength"] = context_length(show)
        except Exception:
            pass
        ps = loaded.get(name)
        if ps:
            info["loaded"] = True
            info["sizeVram"] = ps.get("size_vram") or 0
        models.append(info)

    models.sort(key=lambda x: x["name"].lower())
    return {"running": True, "version": version, "models": models}


def act(action: str, name: str) -> dict:
    if not NAME_RE.match(name or ""):
        return {"ok": False, "error": "invalid model name"}
    try:
        if action == "unload":
            call("/api/generate", {"model": name, "keep_alive": 0}, timeout=15.0)
        else:
            call("/api/delete", {"model": name, "name": name}, method="DELETE", timeout=30.0)
        return {"ok": True}
    except urllib.error.HTTPError as e:
        return {"ok": False, "error": f"HTTP {e.code}"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "list"
    if cmd == "list":
        out = list_models()
    elif cmd in ("unload", "delete") and len(sys.argv) > 2:
        out = act(cmd, sys.argv[2])
    else:
        out = {"ok": False, "error": "usage: ollama-models.py list | unload NAME | delete NAME"}
    print(json.dumps(out, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
