#!/usr/bin/env python3
"""Ollama model catalog ranked for THIS machine. Helper of the Intelligence "Catalog" page.

  ollama-catalog.py list [--ctx N] [--refresh] [--free-vram]
                                                 one JSON line: hardware + ranked model variants
  ollama-catalog.py refine                       fetch the exact size of every tag (slow, cached;
                                                 prints one JSON progress line per model)
  ollama-catalog.py snapshot PATH                write the bundled offline catalog (maintainers)

Data comes from the public ollama.com/library pages (one request for the list, one per model for
the tag sizes), cached for a day / two weeks in ~/.cache/quickshell/ollama-catalog. Offline, it
falls back to the snapshot shipped in defaults/ai/ollama-catalog.json. Only model names are ever
requested: nothing about you or your PC is sent. Stdlib only. Always exits 0 and prints JSON.

How a variant is judged (all numbers are ESTIMATES, flagged as such in the UI):
  size   exact GB from the tag page when known, else parameters x ~0.6 GB (Q4_K_M)
  need   size + KV cache for the chosen context + ~0.8 GB runtime
  fit    gpu     fits in the GPU memory
         partial GPU + system RAM (slower)
         cpu     system RAM only
         no      does not fit at all
  speed  tokens/s ~ 0.65 x memory bandwidth / bytes read per token (active weights for MoE);
         models you benchmarked (ollama-bench.py) show the measured speed, and the measurements
         calibrate the GPU bandwidth used for the others
  vram   with --free-vram only the VRAM not taken by other apps right now counts
  score  quality (parameters, popularity, recency, tools) x usability (fit and speed)
"""
import concurrent.futures
import importlib.util
import json
import math
import os
import re
import subprocess
import sys
import time
import urllib.request

BASE = "https://ollama.com"
UA = "end4-pC-Custom model catalog (https://github.com/jeffersonmk/end4-pC-Custom)"
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "quickshell", "ollama-catalog")
HERE = os.path.dirname(os.path.abspath(__file__))
BUNDLED = os.path.normpath(os.path.join(HERE, "..", "..", "defaults", "ai", "ollama-catalog.json"))
LIBRARY_TTL = 24 * 3600
TAGS_TTL = 14 * 24 * 3600
REFINE_MAX = 100
GB = 1024 ** 3

# Mixture-of-experts models: total size is read from the tag, but only the active
# parameters are read for every token, which makes them much faster than a dense model.
MOE_ACTIVE_B = {
    "qwen3:30b": 3.3, "qwen3:235b": 22, "qwen3-coder:30b": 3.3, "gpt-oss:20b": 3.6,
    "gpt-oss:120b": 5.1, "mixtral:8x7b": 12.9, "mixtral:8x22b": 39, "llama4:scout": 17,
    "llama4:maverick": 17, "deepseek-v2:16b": 2.4, "deepseek-v3:671b": 37,
    "granite3.1-moe:1b": 0.4, "granite3.1-moe:3b": 0.8, "olmoe:7b": 1.0,
}

# GPU memory bandwidth in GB/s (name fragment -> value). Rough public specs.
GPU_BANDWIDTH = [
    ("9070 XT", 640), ("9070", 576), ("9060 XT", 320), ("9060", 288), ("9050", 224),
    ("7900 XTX", 960), ("7900 XT", 800), ("7900 GRE", 576), ("7800 XT", 624), ("7700 XT", 432),
    ("7600 XT", 288), ("7600", 288), ("6950", 576), ("6900", 512), ("6800", 512), ("6700", 384),
    ("6600", 224), ("5090", 1792), ("5080", 960), ("5070 Ti", 896), ("5070", 672), ("5060 Ti", 448),
    ("5060", 448), ("4090", 1008), ("4080", 717), ("4070 Ti", 504), ("4070", 504), ("4060 Ti", 288),
    ("4060", 272), ("3090", 936), ("3080", 760), ("3070", 448), ("3060 Ti", 448), ("3060", 360),
    ("2080", 448), ("2070", 448), ("2060", 336), ("1080", 320), ("1070", 256), ("1060", 192),
]

# KV cache bytes per token by parameter count (billions): typical GQA layouts, interpolated.
KV_BYTES = [(0.5, 24_000), (1, 32_000), (3, 114_000), (8, 147_000), (14, 164_000),
            (32, 262_000), (70, 327_000), (400, 600_000)]


# ---------------------------------------------------------------- small helpers

def emit(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def http_get(path: str, timeout=20) -> str:
    req = urllib.request.Request(BASE + path, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def read_json(path: str):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def write_json(path: str, obj) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, ensure_ascii=False)
    os.replace(tmp, path)


def parse_count(text: str) -> float:
    m = re.match(r"([\d.,]+)\s*([KMB]?)", (text or "").strip(), re.I)
    if not m:
        return 0.0
    value = float(m.group(1).replace(",", ""))
    return value * {"": 1, "K": 1e3, "M": 1e6, "B": 1e9}[m.group(2).upper()]


def parse_age_days(text: str) -> int:
    m = re.search(r"(\d+)\s+(day|week|month|year)", text or "")
    if not m:
        return 0 if "hour" in (text or "") or "minute" in (text or "") else 365
    return int(m.group(1)) * {"day": 1, "week": 7, "month": 30, "year": 365}[m.group(2)]


def params_from_tag(tag: str):
    """'8b' -> 8.0, '0.6b' -> 0.6, '270m' -> 0.27, '8x7b' -> 56.0 (None when not a size tag)."""
    m = re.fullmatch(r"(?:(\d+)x)?(\d+(?:\.\d+)?)([bm])", tag)
    if not m:
        return None
    value = float(m.group(2)) * (int(m.group(1)) if m.group(1) else 1)
    return value / 1000 if m.group(3) == "m" else value


# ---------------------------------------------------------------- library page

def parse_library(html: str) -> list:
    models = []
    for block in re.split(r"<li\s", html)[1:]:
        m = re.search(r'href="/library/([^"/:]+)"', block)
        if not m:
            continue
        name = m.group(1)
        desc = re.search(r'<p class="max-w-lg[^>]*>(.*?)</p>', block, re.S)
        spans = re.findall(r'<span\s+class="inline-flex items-center rounded-md[^>]*>\s*([^<]+?)\s*</span>', block)
        caps = [s for s in spans if s in ("tools", "vision", "thinking", "embedding", "cloud")]
        sizes = [s for s in spans if s not in caps]
        pulls = re.search(r"<span\s*>([\d.,]+[KMB]?)</span>\s*<span[^>]*>&nbsp;Pulls", block)
        tags = re.search(r"<span\s*>(\d+)</span>\s*<span[^>]*>&nbsp;Tags", block)
        age = re.search(r"Updated&nbsp;</span>\s*<span\s*>([^<]+)</span>", block)
        text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", desc.group(1))).strip() if desc else ""
        models.append({
            "name": name,
            "description": text.replace("&amp;", "&").replace("&#39;", "'").replace("&quot;", '"'),
            "capabilities": caps,
            "sizes": sizes,
            "pulls": parse_count(pulls.group(1)) if pulls else 0,
            "tagCount": int(tags.group(1)) if tags else 0,
            "updatedDays": parse_age_days(age.group(1)) if age else 365,
        })
    return models


def load_library(force: bool):
    """(models, source, fetched_at). Cache first, then network, then the bundled snapshot."""
    path = os.path.join(CACHE, "library.json")
    cached = read_json(path)
    if cached and not force and time.time() - cached.get("fetchedAt", 0) < LIBRARY_TTL:
        return cached["models"], "cache", cached["fetchedAt"]
    try:
        models = parse_library(http_get("/library", 25))
        if len(models) >= 20:
            fetched = time.time()
            write_json(path, {"fetchedAt": fetched, "models": models})
            return models, "network", fetched
    except Exception:
        pass
    if cached:
        return cached["models"], "cache", cached.get("fetchedAt", 0)
    bundled = read_json(BUNDLED)
    if bundled:
        return bundled["models"], "bundled", bundled.get("fetchedAt", 0)
    return [], "none", 0


# ---------------------------------------------------------------- tag pages (exact sizes)

TAG_HEAD = re.compile(r'href="/library/([^"/:]+):([^"]+)"\s+class="md:hidden')


def parse_tags(html: str) -> dict:
    """tag -> {gb, context, input} from the compact (mobile) rows of the tags page."""
    out = {}
    heads = list(TAG_HEAD.finditer(html))
    for i, m in enumerate(heads):
        tag = m.group(2)
        if tag in out:
            continue
        seg = html[m.end(): heads[i + 1].start() if i + 1 < len(heads) else len(html)]
        seg = seg[:900]
        size = re.search(r"([\d.]+)\s*(GB|MB)", seg)
        if not size:
            continue
        ctx = re.search(r"(\d+(?:\.\d+)?)\s*([KM])\s*context window", seg)
        inp = re.search(r"((?:Text|Image|Audio|Video)[\w, ]*?)\s+input", seg)
        gb = float(size.group(1)) * (1 if size.group(2) == "GB" else 1 / 1024)
        out[tag] = {
            "gb": round(gb, 2),
            "context": int(float(ctx.group(1)) * (1024 if ctx.group(2) == "K" else 1024 * 1024)) if ctx else None,
            "input": inp.group(1).strip() if inp else "Text",
        }
    return out


def tag_cache_path(name: str) -> str:
    return os.path.join(CACHE, "tags", re.sub(r"[^\w.-]", "_", name) + ".json")


def cached_tags(name: str):
    c = read_json(tag_cache_path(name))
    if c and time.time() - c.get("fetchedAt", 0) < TAGS_TTL:
        return c["tags"]
    return None


def refine() -> None:
    models, source, _ = load_library(False)
    # The most popular models only (the rest keep estimated sizes): fewer requests to ollama.com
    popular = [m for m in sorted(models, key=lambda m: -m["pulls"])
               if m["sizes"] and "embedding" not in m["capabilities"]][:REFINE_MAX]
    todo = [m for m in popular if cached_tags(m["name"]) is None]
    emit({"phase": "start", "total": len(todo)})
    done = 0

    def work(m):
        try:
            tags = parse_tags(http_get(f"/library/{m['name']}/tags", 25))
            write_json(tag_cache_path(m["name"]), {"fetchedAt": time.time(), "tags": tags})
        except Exception:
            pass
        return m["name"]

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for _ in pool.map(work, todo):
            done += 1
            if done % 10 == 0 or done == len(todo):
                emit({"phase": "refine", "done": done, "total": len(todo)})
    emit({"ok": True, "done": done})


# ---------------------------------------------------------------- hardware

def load_health_module():
    spec = importlib.util.spec_from_file_location("ollama_health", os.path.join(HERE, "ollama-health.py"))
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def gpu_bandwidth(name: str, vram_gb: float) -> float:
    for fragment, bw in GPU_BANDWIDTH:
        if fragment in name:
            return float(bw)
    return 250 if vram_gb <= 8 else 400 if vram_gb <= 12 else 450 if vram_gb <= 16 else 800


def meminfo() -> dict:
    out = {}
    try:
        for line in open("/proc/meminfo"):
            k, v = line.split(":", 1)
            out[k] = int(v.split()[0]) * 1024
    except Exception:
        pass
    return out


def vram_used_bytes():
    """Bytes of GPU memory in use right now (all apps), or None when unknown."""
    best, used = 0, None
    try:
        for card in os.listdir("/sys/class/drm"):
            base = f"/sys/class/drm/{card}/device"
            if re.fullmatch(r"card\d+", card) and os.path.exists(base + "/mem_info_vram_total"):
                total = int(open(base + "/mem_info_vram_total").read())
                if total > best:
                    best, used = total, int(open(base + "/mem_info_vram_used").read())
    except Exception:
        pass
    if used is None:
        try:
            out = subprocess.run(["nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits"],
                                 capture_output=True, text=True, timeout=5).stdout.split()
            if out:
                used = int(float(out[0])) * 1024 * 1024
        except Exception:
            pass
    return used


def ollama_vram_bytes() -> int:
    """GPU memory held by models Ollama has loaded (it is not 'other apps')."""
    try:
        health = load_health_module()
        return sum((m.get("size_vram") or 0) for m in health.api("/api/ps").get("models") or [])
    except Exception:
        return 0


def hardware(free_vram: bool = False) -> dict:
    gpu_name, vram = "", 0
    try:
        health = load_health_module()
        devs = [d for d in health.devices_from_log() if d["library"].lower() not in ("", "cpu")]
        if devs:
            gpu_name, vram = devs[0]["name"], devs[0]["total"]
        else:
            gpus = [g for g in health.gpus() if g["vram"] >= 2 * GB]  # skip iGPUs
            if gpus:
                gpu_name, vram = gpus[0]["name"], gpus[0]["vram"]
    except Exception:
        pass
    mem = meminfo()
    total_gb = vram / GB
    used = vram_used_bytes() if vram else None
    others_gb = max(0.0, ((used or 0) - ollama_vram_bytes()) / GB) if used is not None else 0.0
    vram_gb = max(0.0, total_gb - others_gb) if free_vram else total_gb
    return {
        "gpuName": gpu_name,
        "vramTotalGb": round(total_gb, 1),
        "vramFreeGb": round(max(0.0, total_gb - (used or 0) / GB), 1) if used is not None else None,
        "vramOthersGb": round(others_gb, 1),
        "freeVramMode": free_vram,
        "vramGb": round(vram_gb, 1),
        "ramGb": round(mem.get("MemTotal", 0) / GB, 1),
        "ramAvailGb": round(mem.get("MemAvailable", 0) / GB, 1),
        "threads": os.cpu_count() or 1,
        "gpuBandwidth": gpu_bandwidth(gpu_name, vram_gb) if vram else 0,
        "ramBandwidth": 40,  # dual-channel DDR4-3200; a benchmark could refine this later
    }


# ---------------------------------------------------------------- judging a variant

def kv_gb(params_b: float, ctx: int) -> float:
    pts = KV_BYTES
    if params_b <= pts[0][0]:
        per = pts[0][1]
    elif params_b >= pts[-1][0]:
        per = pts[-1][1]
    else:
        per = pts[-1][1]
        for (p0, b0), (p1, b1) in zip(pts, pts[1:]):
            if p0 <= params_b <= p1:
                per = b0 + (b1 - b0) * (params_b - p0) / (p1 - p0)
                break
    return per * ctx / GB


def judge(size_gb: float, params_b: float, active_b: float, ctx: int, hw: dict) -> dict:
    need = size_gb + kv_gb(params_b, ctx) + 0.8
    vram = hw["vramGb"] * 0.95
    ram = max(hw["ramAvailGb"], hw["ramGb"] * 0.5) * 0.85
    gpu_bw, ram_bw = hw["gpuBandwidth"], hw["ramBandwidth"]
    # bytes read per generated token: the active share of the weights
    active_gb = size_gb * (active_b / params_b if params_b > 0 else 1)
    if vram > 0 and need <= vram:
        fit, tps = "gpu", 0.65 * gpu_bw / max(active_gb, 0.1)
    elif vram > 0 and need <= vram + ram:
        gpu_frac = vram / need
        fit = "partial"
        tps = 1 / (gpu_frac / (0.65 * gpu_bw / max(active_gb, 0.1)) + (1 - gpu_frac) / (0.65 * ram_bw / max(active_gb, 0.1)))
    elif need <= ram:
        fit, tps = "cpu", 0.65 * ram_bw / max(active_gb, 0.1)
    else:
        fit, tps = "no", 0.0
    return {"fit": fit, "needGb": round(need, 1), "tps": round(tps, 1)}


def quality(params_b: float, active_b: float, pulls: float, days: int, tools: bool) -> float:
    eff = math.sqrt(params_b * active_b) if active_b < params_b else params_b  # MoE: geometric mean
    q_size = min(1, max(0, (math.log2(max(eff, 0.25)) + 2) / 10))
    q_pop = min(1, max(0, (math.log10(max(pulls, 1)) - 3) / 5))
    q_new = 1 - min(days, 730) / 730
    return 100 * (0.55 * q_size + 0.30 * q_pop + 0.10 * q_new + 0.05 * (1 if tools else 0))


def usability(j: dict) -> float:
    fit = {"gpu": 1.0, "partial": 0.65, "cpu": 0.35, "no": 0.0}[j["fit"]]
    speed = min(1.0, max(0.25, j["tps"] / 25))
    return fit * (0.4 + 0.6 * speed)


def bench_path() -> str:
    return os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                        "quickshell", "user", "ai", "ollama-bench.json")


def calibration(variants: list, bench: dict) -> tuple:
    """(factor, count): measured / estimated speed of benchmarked models that ran fully on the GPU."""
    ratios = []
    for v in variants:
        b = bench.get(v["id"])
        # tiny models are limited by overheads, not by memory bandwidth: they say nothing about big ones
        if b and v["fit"] == "gpu" and b.get("gpuPercent", 0) >= 95 and v["estimatedTps"] > 0 and v["sizeGb"] >= 2.0:
            ratios.append(b["tps"] / v["estimatedTps"])
    if not ratios:
        return 1.0, 0
    ratios.sort()
    mid = ratios[len(ratios) // 2]
    return min(2.0, max(0.3, mid)), len(ratios)


def build_variants(models: list, ctx: int, hw: dict, bench: dict, gpu_factor: float = 1.0) -> list:
    hw = dict(hw, gpuBandwidth=hw["gpuBandwidth"] * gpu_factor)
    out = []
    for m in models:
        caps = set(m["capabilities"]) - {"cloud"}
        cloud_only = "cloud" in m["capabilities"] and not any(params_from_tag(s) is not None for s in m["sizes"])
        if cloud_only:
            continue  # runs on ollama.com servers, not on this PC
        tags = cached_tags(m["name"]) or {}
        # size tags only (8b, 0.6b, 8x7b, 270m); latest-only models keep their latest tag
        wanted = [t for t in tags if params_from_tag(t) is not None]
        if not wanted:
            wanted = [s for s in m["sizes"] if params_from_tag(s) is not None]
        if not wanted and tags.get("latest"):
            wanted = ["latest"]
        for tag in wanted:
            params = params_from_tag(tag)
            detail = tags.get(tag) or (tags.get("latest") if tag == "latest" else None)
            if params is None:  # "latest": derive from the size when the tag page knows it
                if not detail:
                    continue
                params = detail["gb"] / 0.6
            exact = detail is not None
            size_gb = detail["gb"] if exact else round(params * 0.6 + 0.2, 2)
            key = f"{m['name']}:{tag}"
            active = MOE_ACTIVE_B.get(key, params)
            moe = active < params
            is_embedding = "embedding" in caps
            j = judge(size_gb, params, active, ctx, hw)
            vision = "vision" in caps or "image" in (detail or {}).get("input", "").lower()
            code = bool(re.search(r"\bcode|coder\b", m["name"] + " " + m["description"], re.I))
            q = quality(params, active, m["pulls"], m["updatedDays"], "tools" in caps)
            measured = bench.get(key)
            estimated_tps = j["tps"]
            if measured:
                j = dict(j, tps=measured["tps"])
            score = 0.0 if is_embedding else round(q * usability(j), 1)
            out.append({
                "id": key,
                "model": m["name"],
                "tag": tag,
                "description": m["description"],
                "capabilities": sorted(caps | ({"vision"} if vision else set()) | ({"code"} if code else set())),
                "paramsB": round(params, 2),
                "activeB": round(active, 2),
                "moe": moe,
                "sizeGb": size_gb,
                "sizeExact": exact,
                "contextK": round(detail["context"] / 1024) if exact and detail.get("context") else None,
                "pulls": m["pulls"],
                "updatedDays": m["updatedDays"],
                "fit": j["fit"],
                "needGb": j["needGb"],
                "tps": j["tps"],
                "estimatedTps": estimated_tps,
                "measured": measured is not None,
                "measuredGpuPercent": measured["gpuPercent"] if measured else None,
                "score": score,
                "embedding": is_embedding,
            })
    out.sort(key=lambda v: (-v["score"], -v["pulls"]))
    rank = 0
    for v in out:
        if v["embedding"]:
            v["rank"] = None  # embedding models can't chat, so they are not ranked
        else:
            rank += 1
            v["rank"] = rank
    return out


def list_cmd(ctx: int, force: bool, free_vram: bool) -> None:
    models, source, fetched = load_library(force)
    if not models:
        return emit({"ok": False, "error": "no-catalog"})
    hw = hardware(free_vram)
    bench = (read_json(bench_path()) or {})
    variants = build_variants(models, ctx, hw, bench)
    factor, count = calibration(variants, bench)
    if count:
        variants = build_variants(models, ctx, hw, bench, factor)
    hw["calibratedBy"] = count
    hw["calibrationFactor"] = round(factor, 2)
    hw["benchmarks"] = len(bench)
    exact = sum(1 for v in variants if v["sizeExact"])
    emit({"ok": True, "source": source, "fetchedAt": fetched, "ctx": ctx, "hardware": hw,
          "variants": variants, "exactSizes": exact})


def snapshot(path: str) -> None:
    models, source, fetched = load_library(True)
    if source != "network":
        return emit({"ok": False, "error": f"not fetched from the network ({source})"})
    write_json(path, {"fetchedAt": fetched, "models": models})
    emit({"ok": True, "models": len(models)})


def main() -> None:
    args = sys.argv[1:]
    cmd = args[0] if args else "list"

    def opt(name, default):
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default

    if cmd == "list":
        list_cmd(int(opt("--ctx", "32768")), "--refresh" in args, "--free-vram" in args)
    elif cmd == "refine":
        refine()
    elif cmd == "snapshot" and len(args) > 1:
        snapshot(args[1])
    else:
        emit({"ok": False, "error": "usage: ollama-catalog.py list|refine|snapshot"})


if __name__ == "__main__":
    main()
