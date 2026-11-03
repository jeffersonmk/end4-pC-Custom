#!/usr/bin/env python3
"""Ollama health, start/stop, model storage disks. Helper of the Intelligence panel.

  ollama-health.py status                      JSON: running, owner, version, runners, devices, hint
  ollama-health.py start [--models-dir DIR] [--require-mount MNT]
  ollama-health.py stop
  ollama-health.py disks                       JSON: mounted disks where models could live
  ollama-health.py scan [DIR ...]              JSON: folders that already hold Ollama models
  ollama-health.py move SRC DST                copy models SRC -> DST, verify, then delete SRC
                                               (prints one JSON line per progress step)

The shell owns its Ollama: `start` runs `ollama serve` as a transient *user* systemd unit
(default name shell-ollama, override with OLLAMA_UNIT), so it survives a shell restart and
needs no root. A server started some other way (the `ollama.service` system unit, a terminal)
is reported as such and never stopped from here.

Talks to the local Ollama HTTP API only (OLLAMA_HOST honoured). Stdlib only. Prints JSON and
exits 0 even on failure ({"ok": false, "error": ...}) so the caller never parses stderr.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request

UNIT = os.environ.get("OLLAMA_UNIT", "shell-ollama")
HOME = os.path.expanduser("~")
DEFAULT_MODELS = os.path.join(HOME, ".ollama", "models")
GIB = 1024 ** 3


def base_url() -> str:
    host = os.environ.get("OLLAMA_HOST", "").strip() or "127.0.0.1:11434"
    if "://" not in host:
        host = "http://" + host
    host = host.replace("//:", "//127.0.0.1:").replace("//0.0.0.0", "//127.0.0.1")
    return host.rstrip("/")


def api(path: str, timeout=2.5):
    with urllib.request.urlopen(base_url() + path, timeout=timeout) as r:
        return json.loads(r.read().decode() or "{}")


def api_version():
    try:
        return api("/api/version").get("version") or ""
    except Exception:
        return None


def run(cmd, timeout=10):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except Exception as e:
        return 1, "", str(e)


def unit_active(unit: str, user: bool) -> bool:
    cmd = ["systemctl"] + (["--user"] if user else []) + ["is-active", unit]
    return run(cmd, 4)[1].strip() == "active"


# ---------------------------------------------------------------- status

def runners() -> list:
    found = {"cpu"}
    for lib in ("/usr/lib/ollama", "/usr/local/lib/ollama", "/usr/lib64/ollama"):
        try:
            for name in os.listdir(lib):
                for key in ("cuda", "rocm", "vulkan"):
                    if name.startswith(key) and os.path.isdir(os.path.join(lib, name)):
                        found.add(key)
        except OSError:
            pass
    order = ["cuda", "rocm", "vulkan", "cpu"]
    return [r for r in order if r in found]


KV = re.compile(r'(\w+)=("[^"]*"|\S+)')


def to_bytes(text: str) -> int:
    m = re.match(r"([\d.]+)\s*([KMGT]i?B)", text or "")
    if not m:
        return 0
    mult = {"K": 1024, "M": 1024 ** 2, "G": GIB, "T": 1024 ** 4}[m.group(2)[0]]
    return int(float(m.group(1)) * mult)


def devices_from_log() -> list:
    """GPUs / backend the running server picked, read from its own start-up log."""
    rc, out, _ = run(["journalctl", "--user", "-u", UNIT, "-o", "cat", "--no-pager", "-n", "600"], 8)
    if rc != 0:
        return []
    lines = out.splitlines()
    start = 0
    for i, line in enumerate(lines):
        if "Listening on" in line:
            start = i
    devs = []
    for line in lines[start:]:
        if "inference compute" not in line:
            continue
        kv = {k: v.strip('"') for k, v in KV.findall(line)}
        devs.append({
            "library": kv.get("library", ""),
            "name": kv.get("description") or kv.get("name", ""),
            "compute": kv.get("compute", ""),
            "type": kv.get("type", ""),
            "total": to_bytes(kv.get("total", "")),
            "available": to_bytes(kv.get("available", "")),
        })
    return devs


def gpus() -> list:
    out = []
    rc, text, _ = run(["lspci", "-mm"], 5)
    for line in text.splitlines():
        if re.search(r'"(VGA compatible controller|3D controller|Display controller)"', line):
            parts = re.findall(r'"([^"]*)"', line)
            # lspci -mm: "class" "vendor" "device" ["subvendor" "subdevice"]
            if len(parts) >= 3:
                vendor, device = parts[1], parts[2]
                short = "AMD" if ("AMD" in vendor or "ATI" in vendor) else "NVIDIA" if "NVIDIA" in vendor else "Intel" if "Intel" in vendor else vendor
                m = re.search(r"\[(.+)\]", device)  # "Navi 44 [Radeon RX 9050 / 9060 XT]" -> the marketing name
                out.append({"vendor": vendor, "name": f"{short} {m.group(1) if m else device}", "vram": 0})
    # AMD exposes its VRAM size in sysfs
    best = 0
    try:
        for card in os.listdir("/sys/class/drm"):
            p = f"/sys/class/drm/{card}/device/mem_info_vram_total"
            if re.fullmatch(r"card\d+", card) and os.path.exists(p):
                best = max(best, int(open(p).read().strip()))
    except Exception:
        pass
    for g in out:
        if "AMD" in g["vendor"] or "ATI" in g["vendor"]:
            g["vram"] = max(g["vram"], best)
    return out


def package_hint(rs: list, gs: list, devs: list, running: bool):
    """What to do so the GPU is actually used, or None when nothing is needed."""
    if not gs:
        return None
    gpu_runner = [r for r in rs if r != "cpu"]
    vendor = gs[0]["vendor"]
    pacman = shutil.which("pacman") is not None
    if not gpu_runner:
        pkg = "ollama-cuda" if "NVIDIA" in vendor else ("ollama-rocm" if ("AMD" in vendor or "ATI" in vendor) else "ollama-vulkan")
        return {"kind": "install", "package": pkg,
                "command": f"sudo pacman -S {pkg}" if pacman else ""}
    if running and devs and all(d["library"].lower() in ("", "cpu") for d in devs):
        return {"kind": "not-detected", "package": "", "command": ""}
    return None


def status() -> dict:
    version = api_version()
    running = version is not None
    shell_owned = unit_active(UNIT, True)
    system_owned = unit_active("ollama", False)
    owner = None
    if running:
        owner = "shell" if shell_owned else ("system" if system_owned else "external")
    rs = runners()
    gs = gpus()
    devs = devices_from_log() if shell_owned else []
    loaded_on_gpu = False
    if running:
        try:
            loaded_on_gpu = any((m.get("size_vram") or 0) > 0 for m in api("/api/ps").get("models") or [])
        except Exception:
            pass
    return {
        "installed": shutil.which("ollama") is not None,
        "running": running,
        "version": version or "",
        "owner": owner,
        "host": base_url(),
        "runners": rs,
        "gpus": gs,
        "devices": devs,
        "loadedOnGpu": loaded_on_gpu,
        "hint": package_hint(rs, gs, devs, running),
    }


# ---------------------------------------------------------------- start / stop

def wait_api(up: bool, seconds: float) -> bool:
    end = time.time() + seconds
    while time.time() < end:
        if (api_version() is not None) == up:
            return True
        time.sleep(0.4)
    return (api_version() is not None) == up


def start(models_dir: str, require_mount: str) -> dict:
    binary = shutil.which("ollama")
    if not binary:
        return {"ok": False, "error": "not-installed"}
    if api_version() is not None:
        st = status()
        return {"ok": False, "error": "already-running", "owner": st["owner"]}
    if require_mount and not os.path.ismount(require_mount):
        return {"ok": False, "error": "disk-not-mounted", "mount": require_mount}
    target = models_dir or DEFAULT_MODELS
    try:
        os.makedirs(target, exist_ok=True)
    except OSError as e:
        return {"ok": False, "error": f"cannot-create-dir: {e}"}
    cmd = ["systemd-run", "--user", f"--unit={UNIT}", "--collect",
           "--description=Ollama (started by the desktop shell)",
           "-E", f"OLLAMA_MODELS={target}"]
    if os.environ.get("OLLAMA_HOST"):
        cmd += ["-E", f"OLLAMA_HOST={os.environ['OLLAMA_HOST']}"]
    cmd += [binary, "serve"]
    rc, _, err = run(cmd, 10)
    if rc != 0:
        return {"ok": False, "error": err.strip() or "systemd-run failed"}
    if not wait_api(True, 20):
        return {"ok": False, "error": "did-not-start"}
    return {"ok": True}


def stop() -> dict:
    if not unit_active(UNIT, True):
        if api_version() is not None:
            return {"ok": False, "error": "not-owned"}
        return {"ok": True}
    run(["systemctl", "--user", "stop", UNIT], 20)
    if not wait_api(False, 15):
        return {"ok": False, "error": "did-not-stop"}
    return {"ok": True}


# ---------------------------------------------------------------- disks

SKIP_FS = {"swap", "vfat", "squashfs", "iso9660", "tmpfs", "devtmpfs", "overlay", "fuse.overlayfs", "efivarfs"}
SKIP_MOUNT = ("/boot", "/efi", "/run", "/sys", "/proc", "/dev", "/var/lib/snapd", "/snap")


def disks() -> dict:
    rc, out, _ = run(["lsblk", "-J", "-b", "-o",
                      "NAME,KNAME,TYPE,FSTYPE,SIZE,ROTA,TRAN,MOUNTPOINTS,LABEL,MODEL,RM"], 8)
    try:
        tree = json.loads(out)["blockdevices"]
    except Exception:
        return {"disks": []}

    result = {}

    def walk(node, root, crypt):
        is_crypt = crypt or node.get("type") == "crypt"
        mounts = [m for m in (node.get("mountpoints") or []) if m and not m.startswith("[")]
        fs = node.get("fstype") or ""
        if mounts and fs not in SKIP_FS:
            good = [m for m in mounts if not m.startswith(SKIP_MOUNT)]
            if good:
                result[node["kname"]] = (node, root, good, is_crypt)
        for child in node.get("children") or []:
            walk(child, root, is_crypt)

    for disk in tree:
        if disk.get("type") != "disk":
            continue
        walk(disk, disk, False)

    try:
        home_dev = os.stat(HOME).st_dev
    except OSError:
        home_dev = None

    entries = []
    for kname, (node, root, mounts, encrypted) in result.items():
        try:
            devs = {m: os.stat(m).st_dev for m in mounts}
        except OSError:
            continue
        holds_home = home_dev is not None and home_dev in devs.values()
        mount = ("/home" if "/home" in mounts else "/" if "/" in mounts else sorted(mounts, key=len)[0])
        if holds_home:
            path = DEFAULT_MODELS
            anchor = mount
        else:
            path = os.path.join(mount, "ollama-models")
            anchor = mount
        try:
            st = os.statvfs(mount)
        except OSError:
            continue
        tran = (root.get("tran") or "").lower()
        rota = root.get("rota")
        if tran == "nvme":
            kind = "NVMe"
        elif tran == "usb":
            kind = "USB"
        elif rota in (False, 0, "0"):
            kind = "SSD"
        else:
            kind = "HDD"
        if holds_home:
            writable = os.access(HOME, os.W_OK)
        else:
            writable = os.access(path if os.path.exists(path) else mount, os.W_OK)
        entries.append({
            "id": kname,
            "kind": kind,
            "model": (root.get("model") or "").strip(),
            "label": (node.get("label") or "").strip(),
            "fstype": node.get("fstype") or "",
            "mount": mount,
            "anchor": anchor,
            "path": path,
            "size": st.f_blocks * st.f_frsize,
            "free": st.f_bavail * st.f_frsize,
            "writable": writable,
            "system": holds_home or "/" in mounts,
            "encrypted": encrypted,
            "removable": bool(root.get("rm")) or tran == "usb",
        })
    entries.sort(key=lambda d: (not d["system"], d["mount"]))
    return {"disks": entries}


# ---------------------------------------------------------------- existing models

def dir_bytes(path: str) -> int:
    total = 0
    for base, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(base, f))
            except OSError:
                pass
    return total


# Ollama keeps blobs plus one manifests folder per format version (manifests, manifests-v2)
MANIFEST_DIRS = ("manifests", "manifests-v2")
MOVABLE = ("blobs",) + MANIFEST_DIRS


def has_models(path: str) -> bool:
    return any(os.path.isdir(os.path.join(path, d)) for d in MANIFEST_DIRS)


def model_count(path: str) -> int:
    # The same model is listed in every format folder, so take the largest count, not the sum
    best = 0
    for d in MANIFEST_DIRS:
        n = sum(len(files) for _b, _d, files in os.walk(os.path.join(path, d)))
        best = max(best, n)
    return best


def scan(extra: list) -> dict:
    cands = [DEFAULT_MODELS, "/var/lib/ollama/models", "/var/lib/ollama",
             "/usr/share/ollama/.ollama/models"] + extra
    seen, out = set(), []
    for c in cands:
        real = os.path.realpath(c)
        if real in seen or not has_models(real):
            continue
        seen.add(real)
        out.append({"path": c, "models": model_count(real), "bytes": dir_bytes(real)})
    return {"found": out}


# ---------------------------------------------------------------- move

def emit(obj) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def move(src: str, dst: str) -> None:
    src, dst = os.path.realpath(src), os.path.realpath(dst) if os.path.exists(dst) else os.path.abspath(dst)
    if api_version() is not None:
        return emit({"ok": False, "error": "ollama-running"})
    if not has_models(src):
        return emit({"ok": False, "error": "no-models-in-source"})
    if src == dst or dst.startswith(src + os.sep) or src.startswith(dst + os.sep):
        return emit({"ok": False, "error": "same-or-nested-folder"})
    try:
        os.makedirs(dst, exist_ok=True)
    except OSError as e:
        return emit({"ok": False, "error": f"cannot-create-dir: {e}"})

    total = sum(dir_bytes(os.path.join(src, d)) for d in MOVABLE if os.path.isdir(os.path.join(src, d)))
    free = shutil.disk_usage(dst).free
    if total * 1.02 > free:
        return emit({"ok": False, "error": "not-enough-space", "needed": total, "free": free})

    emit({"phase": "copy", "percent": 0, "bytes": total})
    cmd = ["rsync", "-a", "--info=progress2", "--no-inc-recursive"]
    for d in MOVABLE:
        cmd += ["--include", f"/{d}/***"]
    cmd += ["--exclude", "*", src + "/", dst + "/"]
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    except FileNotFoundError:
        return emit({"ok": False, "error": "rsync-missing"})
    last = -1
    assert p.stdout is not None
    for chunk in iter(p.stdout.readline, ""):
        for m in re.finditer(r"(\d+)%", chunk):
            pct = int(m.group(1))
            if pct != last:
                last = pct
                emit({"phase": "copy", "percent": pct})
    if p.wait() != 0:
        return emit({"ok": False, "error": "copy-failed", "note": "nothing was deleted"})

    # Verify: a second pass must have nothing left to transfer
    emit({"phase": "verify"})
    vcmd = ["rsync", "-a", "--no-inc-recursive"] + [x for d in MOVABLE for x in ("--include", f"/{d}/***")]
    chk = subprocess.run(vcmd + ["--exclude", "*", "--dry-run", "--itemize-changes", src + "/", dst + "/"],
                         capture_output=True, text=True)
    pending = [l for l in chk.stdout.splitlines() if l.strip() and not l.startswith(".d")]
    if chk.returncode != 0 or pending:
        return emit({"ok": False, "error": "verify-failed", "note": "nothing was deleted"})

    emit({"phase": "cleanup"})
    for d in MOVABLE:
        shutil.rmtree(os.path.join(src, d), ignore_errors=True)
    emit({"ok": True, "phase": "done", "bytes": total})


def main() -> None:
    args = sys.argv[1:]
    cmd = args[0] if args else "status"

    def opt(name):
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else ""

    if cmd == "status":
        emit(status())
    elif cmd == "start":
        emit(start(opt("--models-dir"), opt("--require-mount")))
    elif cmd == "stop":
        emit(stop())
    elif cmd == "disks":
        emit(disks())
    elif cmd == "scan":
        emit(scan(args[1:]))
    elif cmd == "move" and len(args) >= 3:
        move(args[1], args[2])
    else:
        emit({"ok": False, "error": "usage: ollama-health.py status|start|stop|disks|scan|move"})


if __name__ == "__main__":
    main()
