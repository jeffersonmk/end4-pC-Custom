#!/usr/bin/env python3
"""
Hardware info for the cheat sheet "System" tab.

  hwinfo.py static   -> specs that don't change (CPU, GPU, board, RAM, drives)
  hwinfo.py live     -> current usage/temperatures (CPU, GPU, VRAM, RAM, disks)

Prints one JSON object. Only reads /sys, /proc and unprivileged tools
(lscpu, lsblk, lspci, glxinfo, nvidia-smi); never needs root.
Missing values are null, so it degrades gracefully on other hardware.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time


def read(path, default=None):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return default


def read_int(path):
    v = read(path)
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def run(cmd, timeout=4):
    if not shutil.which(cmd[0]):
        return None
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.SubprocessError):
        return None


def clean(s):
    return re.sub(r"\s+", " ", s or "").strip() or None


# ---------------------------------------------------------------- hwmon
def hwmons():
    out = []
    for h in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        out.append((read(f"{h}/name", ""), h))
    return out


def hwmon_temps(path):
    """{label: celsius} for a hwmon dir."""
    temps = {}
    for inp in sorted(glob.glob(f"{path}/temp*_input")):
        v = read_int(inp)
        if v is None:
            continue
        label = read(inp.replace("_input", "_label")) or os.path.basename(inp).split("_")[0]
        temps[label] = round(v / 1000, 1)
    return temps


def cpu_temp():
    for name, path in hwmons():
        t = hwmon_temps(path)
        if name == "k10temp":  # AMD
            return t.get("Tctl") or t.get("Tdie") or next(iter(t.values()), None)
        if name == "coretemp":  # Intel
            pkg = next((v for k, v in t.items() if k.startswith("Package")), None)
            return pkg or (max(t.values()) if t else None)
        if name in ("zenpower", "cpu_thermal", "acpitz") and t:
            return next(iter(t.values()))
    return None


# ---------------------------------------------------------------- CPU
def cpu_static():
    info = {}
    out = run(["lscpu", "-J"])
    if out:
        try:
            for e in json.loads(out)["lscpu"]:
                info[e["field"].rstrip(":")] = e.get("data")
        except (ValueError, KeyError):
            pass
    model = info.get("Model name")
    threads = int(info["CPU(s)"]) if (info.get("CPU(s)") or "").isdigit() else os.cpu_count()
    tpc = info.get("Thread(s) per core")
    # Without lscpu the core count is unknown (threads != cores with SMT)
    cores = threads // int(tpc) if threads and tpc and str(tpc).isdigit() else None
    max_mhz = info.get("CPU max MHz")
    return {
        "model": clean(model),
        "cores": cores,
        "threads": threads,
        "maxGhz": round(float(max_mhz) / 1000, 2) if max_mhz else None,
        "l3": clean(info.get("L3 cache") or info.get("L3")),
        "arch": info.get("Architecture"),
    }


def cpu_usage():
    def snap():
        parts = read("/proc/stat", "").splitlines()[0].split()[1:]
        nums = list(map(int, parts))
        idle = nums[3] + (nums[4] if len(nums) > 4 else 0)
        return idle, sum(nums)
    i1, t1 = snap()
    time.sleep(0.25)
    i2, t2 = snap()
    dt = t2 - t1
    return round(100 * (1 - (i2 - i1) / dt), 1) if dt > 0 else None


def cpu_freq_ghz():
    vals = [read_int(p) for p in glob.glob("/sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq")]
    vals = [v for v in vals if v]
    return round(sum(vals) / len(vals) / 1e6, 2) if vals else None


# ---------------------------------------------------------------- GPU
def drm_cards():
    cards = []
    for dev in sorted(glob.glob("/sys/class/drm/card[0-9]*/device")):
        card = dev.split("/")[-2]
        if "-" in card:
            continue
        vendor = read(f"{dev}/vendor")
        cards.append((card, dev, vendor))
    return cards


def lspci_name(dev):
    slot = os.path.basename(os.path.realpath(dev))
    out = run(["lspci", "-mm", "-s", slot])
    if not out:
        return None
    m = re.findall(r'"([^"]*)"', out)
    # "class" "vendor" "device" ...
    if len(m) >= 3:
        name = m[2]
        br = re.search(r"\[(.+)\]", name)
        return clean(br.group(1) if br else name)
    return None


def nvidia_query(fields):
    out = run(["nvidia-smi", f"--query-gpu={fields}", "--format=csv,noheader,nounits"])
    if not out:
        return []
    return [[c.strip() for c in line.split(",")] for line in out.strip().splitlines()]


def gpu_static():
    gpus = []
    glx = run(["glxinfo", "-B"]) or ""
    glx_name = re.search(r"Device: (.+?) \(", glx)
    for card, dev, vendor in drm_cards():
        g = {"card": card, "vendor": {"0x1002": "AMD", "0x10de": "NVIDIA", "0x8086": "Intel"}.get(vendor, vendor)}
        driver = os.path.basename(os.path.realpath(f"{dev}/driver")) if os.path.exists(f"{dev}/driver") else None
        g["driver"] = driver
        g["name"] = lspci_name(dev)
        vram = read_int(f"{dev}/mem_info_vram_total")
        g["vramTotal"] = vram
        g["vbios"] = read(f"{dev}/vbios_version")
        if vendor == "0x1002" and glx_name:
            g["name"] = clean(glx_name.group(1)) or g["name"]
        gpus.append(g)
    nv = nvidia_query("name,memory.total,driver_version")
    nv_gpus = [g for g in gpus if g["vendor"] == "NVIDIA"]
    for g, row in zip(nv_gpus, nv):
        g["name"] = row[0]
        g["vramTotal"] = int(float(row[1]) * 1024 * 1024) if row[1] else None
        g["driver"] = f"nvidia {row[2]}"
    # Prefer discrete GPUs (with VRAM) first
    gpus.sort(key=lambda g: -(g.get("vramTotal") or 0))
    return gpus


def gpu_live():
    gpus = []
    nv_rows = nvidia_query("utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,fan.speed")
    nv_i = 0
    for card, dev, vendor in drm_cards():
        g = {"card": card}
        if vendor == "0x10de" and nv_i < len(nv_rows):
            r = nv_rows[nv_i]; nv_i += 1
            num = lambda x: float(x) if re.match(r"^[\d.]+$", x or "") else None
            g.update(busy=num(r[0]), temp=num(r[1]),
                     vramUsed=int(num(r[2]) * 1048576) if num(r[2]) is not None else None,
                     vramTotal=int(num(r[3]) * 1048576) if num(r[3]) is not None else None,
                     power=num(r[4]), fanPercent=num(r[5]))
        else:
            g["busy"] = read_int(f"{dev}/gpu_busy_percent")
            g["vramUsed"] = read_int(f"{dev}/mem_info_vram_used")
            g["vramTotal"] = read_int(f"{dev}/mem_info_vram_total")
            for hw in glob.glob(f"{dev}/hwmon/hwmon*"):
                t = hwmon_temps(hw)
                g["temp"] = t.get("edge") or next(iter(t.values()), None)
                g["tempHotspot"] = t.get("junction")
                g["tempMem"] = t.get("mem")
                p = read_int(f"{hw}/power1_average") or read_int(f"{hw}/power1_input")
                g["power"] = round(p / 1e6, 1) if p else None
                g["fanRpm"] = read_int(f"{hw}/fan1_input")
                f = read_int(f"{hw}/freq1_input")
                g["clockMhz"] = round(f / 1e6) if f else None
        gpus.append(g)
    gpus.sort(key=lambda g: -(g.get("vramTotal") or 0))
    return gpus


# ---------------------------------------------------------------- drives
def drive_temps():
    """{block device name: celsius} from nvme / drivetemp hwmons."""
    temps = {}
    for name, path in hwmons():
        if name not in ("nvme", "drivetemp"):
            continue
        t = hwmon_temps(path)
        if not t:
            continue
        val = t.get("Composite") or next(iter(t.values()))
        real = os.path.realpath(f"{path}/device")
        # hwmon device is the nvme controller (…/nvme/nvme0) or the SCSI disk (drivetemp)
        blocks = (glob.glob(f"{real}/nvme*n*") + glob.glob(f"{real}/nvme*/nvme*n*")
                  + glob.glob(f"{real}/block/*"))
        for b in blocks:
            bn = os.path.basename(b)
            if re.match(r"^(nvme\d+n\d+|sd[a-z]+)$", bn):
                temps[bn] = val
    return temps


def lsblk():
    out = run(["lsblk", "-J", "-b", "-o",
               "NAME,TYPE,SIZE,MODEL,ROTA,TRAN,FSTYPE,FSSIZE,FSUSED,MOUNTPOINTS,LABEL"])
    try:
        return json.loads(out)["blockdevices"] if out else []
    except ValueError:
        return []


def walk(node, acc):
    acc.append(node)
    for c in node.get("children") or []:
        walk(c, acc)
    return acc


def drives(include_usage):
    temps = drive_temps() if include_usage else {}
    result = []
    for d in lsblk():
        if d.get("type") != "disk" or re.match(r"^(loop|zram|ram|sr)", d["name"]):
            continue
        tran = (d.get("tran") or "").lower()
        rota = str(d.get("rota")) in ("1", "True", "true")
        kind = "NVMe SSD" if tran == "nvme" or d["name"].startswith("nvme") else ("HDD" if rota else "SSD")
        if tran == "usb":
            kind = f"USB {'HDD' if rota else 'drive'}"
        entry = {
            "name": d["name"],
            "model": clean(d.get("model")) or d["name"],
            "size": int(d.get("size") or 0),
            "kind": kind,
            "bus": tran.upper() or None,
        }
        if include_usage:
            # Filesystems on this drive (dedupe btrfs subvolume mounts)
            fss, seen = [], set()
            encrypted_locked = False
            for n in walk(d, [])[1:]:
                mps = [m for m in (n.get("mountpoints") or []) if m]
                if n.get("fstype") == "crypto_LUKS" and not n.get("children"):
                    encrypted_locked = True
                if not mps or n.get("fstype") in ("swap", None) or n["name"] in seen:
                    continue
                seen.add(n["name"])
                mp = "/" if "/" in mps else ("/home" if "/home" in mps else sorted(mps, key=len)[0])
                size, used = n.get("fssize"), n.get("fsused")
                if not size:
                    continue
                fss.append({"mount": mp, "fstype": n.get("fstype"),
                            "size": int(size), "used": int(used or 0)})
            fss.sort(key=lambda f: -f["size"])
            entry["filesystems"] = fss
            entry["locked"] = encrypted_locked and not fss
            entry["temp"] = temps.get(d["name"])
        result.append(entry)
    return result


# ---------------------------------------------------------------- memory / board
def meminfo():
    m = {}
    for line in read("/proc/meminfo", "").splitlines():
        k, v = line.split(":", 1)
        m[k] = int(v.split()[0]) * 1024
    return m


def board():
    v = read("/sys/class/dmi/id/board_vendor")
    n = read("/sys/class/dmi/id/board_name")
    return clean(f"{v or ''} {n or ''}")


def os_name():
    for line in read("/etc/os-release", "").splitlines():
        if line.startswith("PRETTY_NAME="):
            return line.split("=", 1)[1].strip('"')
    return None


# ---------------------------------------------------------------- main
def static():
    mem = meminfo()
    return {
        "cpu": cpu_static(),
        "gpus": gpu_static(),
        "board": board(),
        "os": os_name(),
        "kernel": os.uname().release,
        "hostname": os.uname().nodename,
        "ramTotal": mem.get("MemTotal"),
        "drives": drives(False),
    }


def live():
    mem = meminfo()
    total = mem.get("MemTotal", 0)
    return {
        "cpu": {"usage": cpu_usage(), "temp": cpu_temp(), "freqGhz": cpu_freq_ghz()},
        "gpus": gpu_live(),
        "ram": {"total": total, "used": total - mem.get("MemAvailable", 0),
                "swapTotal": mem.get("SwapTotal", 0),
                "swapUsed": mem.get("SwapTotal", 0) - mem.get("SwapFree", 0)},
        "drives": drives(True),
        "uptime": int(float(read("/proc/uptime", "0").split()[0])),
    }


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "live"
    print(json.dumps(static() if mode == "static" else live()))
