#!/usr/bin/env python3
"""Drive health (SMART) for the Super+/ System tab. Prints one JSON object.

Source: UDisks2 over the system D-Bus (busctl), the same data GNOME Disks
shows. It needs neither root nor smartctl: the daemon already holds the
SMART readings and the active session may read them.  This script only
reads the cached values; it never wakes a disk, starts a self-test or
changes anything.

Output: {"drives": [{name, model, kind, supported, verdict, health, temp,
power_on_hours, written, read, updated, reasons[], metrics[]}]}
  - name   : block device (sda, nvme0n1) so the page can match hwinfo.py drives
  - verdict: "good" | "caution" | "bad" | "unknown"
  - health : remaining life in percent, or null when the drive does not say
  - reasons: [{code, level}] what pushed the verdict (level: caution|bad)
  - metrics: [{code, value, level, unit}] per-attribute rows for the details list
             (level: ok|caution|bad|info). Codes are translated by the page.
Anything the drive does not report is null, never a guessed number.
"""
import json
import subprocess
import sys

BUS = "org.freedesktop.UDisks2"
IFACE_DRIVE = "org.freedesktop.UDisks2.Drive"
IFACE_ATA = "org.freedesktop.UDisks2.Drive.Ata"
IFACE_NVME = "org.freedesktop.UDisks2.NVMe.Controller"
IFACE_BLOCK = "org.freedesktop.UDisks2.Block"


def busctl(*args, timeout=5):
    try:
        out = subprocess.run(["busctl", "--system", "--json=short", *args],
                             capture_output=True, text=True, timeout=timeout)
        if out.returncode != 0 or not out.stdout.strip():
            return None
        return json.loads(out.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def props(iface_dict):
    """{name: {"type":..,"data":..}} -> {name: data}"""
    return {k: v.get("data") for k, v in (iface_dict or {}).items()}


def managed_objects():
    res = busctl("call", BUS, "/org/freedesktop/UDisks2",
                 "org.freedesktop.DBus.ObjectManager", "GetManagedObjects")
    if not res or not res.get("data"):
        return {}
    return res["data"][0]


def block_names(objs):
    """{drive object path: block device name} for whole-disk blocks."""
    names = {}
    for path, ifaces in objs.items():
        blk = ifaces.get(IFACE_BLOCK)
        if not blk or "org.freedesktop.UDisks2.Partition" in ifaces:
            continue
        p = props(blk)
        drive = p.get("Drive")
        dev = p.get("Device")
        if not drive or drive == "/" or not dev:
            continue
        try:
            name = bytes(dev).split(b"\0")[0].decode().rsplit("/", 1)[-1]
        except (TypeError, ValueError):
            continue
        if name and not name.startswith(("loop", "zram", "ram", "sr", "dm-")):
            names[drive] = name
    return names


def kelvin_to_c(k):
    # UDisks reports 0 when the drive has no reading
    return round(k - 273.15, 1) if k and k > 0 else None


def add(metrics, code, value, level="info", unit=None, **extra):
    m = {"code": code, "value": value, "level": level, "unit": unit}
    m.update(extra)
    metrics.append(m)


def worst(a, b):
    order = {"good": 0, "caution": 1, "bad": 2}
    return a if order[a] >= order[b] else b


def nvme_health(path, p):
    metrics, reasons = [], []
    attrs = busctl("call", BUS, path, IFACE_NVME, "SmartGetAttributes", "a{sv}", "0")
    a = {k: v.get("data") for k, v in attrs["data"][0].items()} if attrs and attrs.get("data") else {}

    verdict = "good"
    crit = p.get("SmartCriticalWarning")
    # newer UDisks: list of warning names; older: bitmask integer
    crit = len(crit) if isinstance(crit, list) else int(crit or 0)
    if crit:
        verdict = worst(verdict, "bad")
        reasons.append({"code": "critical_warning", "level": "bad"})
    add(metrics, "critical_warning", crit, "bad" if crit else "ok")

    used = a.get("percent_used")
    health = None
    if used is not None:
        health = max(0, min(100, 100 - int(used)))
        lvl = "bad" if used >= 100 else "caution" if used >= 80 else "ok"
        if lvl != "ok":
            verdict = worst(verdict, "bad" if lvl == "bad" else "caution")
            reasons.append({"code": "wear", "level": lvl})
        add(metrics, "wear_used", used, lvl, "%")

    spare, thresh = a.get("avail_spare"), a.get("spare_thresh")
    if spare is not None:
        low = thresh is not None and spare <= thresh
        if low:
            verdict = worst(verdict, "bad")
            reasons.append({"code": "spare_low", "level": "bad"})
        add(metrics, "spare", spare, "bad" if low else "ok", "%", limit=thresh)

    me = a.get("media_errors")
    if me is not None:
        lvl = "caution" if me > 0 else "ok"
        if me > 0:
            verdict = worst(verdict, "caution")
            reasons.append({"code": "media_errors", "level": "caution"})
        add(metrics, "media_errors", me, lvl)

    temp = kelvin_to_c(p.get("SmartTemperature"))
    wc, cc = a.get("wctemp"), a.get("cctemp")
    wc_c = kelvin_to_c(wc) if wc else None
    cc_c = kelvin_to_c(cc) if cc else None
    tlvl = "ok"
    if temp is not None and cc_c and temp >= cc_c:
        tlvl = "bad"
    elif temp is not None and wc_c and temp >= wc_c - 5:
        tlvl = "caution"
    if (a.get("warning_temp_time") or 0) > 0 and tlvl == "ok":
        tlvl = "caution"
    if tlvl != "ok":
        verdict = worst(verdict, "bad" if tlvl == "bad" else "caution")
        reasons.append({"code": "temp_high", "level": tlvl})
    add(metrics, "temperature", temp, tlvl, "C", limit=wc_c)

    add(metrics, "error_log", a.get("num_err_log_entries"))
    add(metrics, "unsafe_shutdowns", a.get("unsafe_shutdowns"))
    add(metrics, "power_cycles", a.get("power_cycles"))
    hours = p.get("SmartPowerOnHours")
    return {
        "verdict": verdict, "health": health, "temp": temp,
        "power_on_hours": hours,
        "written": a.get("total_data_written"), "read": a.get("total_data_read"),
        "reasons": reasons, "metrics": metrics,
    }


# ATA attributes we show: id -> (code, level when raw > 0)
ATA_COUNTERS = {
    5: ("reallocated", "caution"),
    196: ("reallocated_events", "info"),
    197: ("pending", "caution"),
    198: ("uncorrectable", "caution"),
    199: ("crc_errors", "info"),
}
# first match wins; some vendors report life left in a different attribute
ATA_LIFE = [(231, None), (233, None), (232, "endurance-remaining"), (177, None)]


def ata_health(path, p, rotational):
    metrics, reasons = [], []
    res = busctl("call", BUS, path, IFACE_ATA, "SmartGetAttributes", "a{sv}", "0")
    table = {}
    if res and res.get("data"):
        for row in res["data"][0]:
            # y id, s name, q flags, i value, i worst, i threshold, x pretty, i unit, a{sv}
            aid, name, _flags, value, _worst, thr, pretty, unit = row[:8]
            table[aid] = {"name": name, "value": value, "threshold": thr,
                          "pretty": pretty, "unit": unit}

    verdict = "good"
    if p.get("SmartFailing"):
        verdict = "bad"
        reasons.append({"code": "failing", "level": "bad"})
    if (p.get("SmartNumAttributesFailing") or 0) > 0:
        verdict = "bad"
        reasons.append({"code": "attr_failing", "level": "bad"})
    elif (p.get("SmartNumAttributesFailedInThePast") or 0) > 0:
        verdict = worst(verdict, "caution")
        reasons.append({"code": "past_failure", "level": "caution"})

    health = None
    for aid, want in ATA_LIFE:
        t = table.get(aid)
        if not t or (want and t["name"] != want):
            continue
        # 177 is only a life gauge on drives that normalise it downwards from 100
        if aid == 177 and not (0 < t["value"] <= 100):
            continue
        health = max(0, min(100, int(t["value"])))
        lvl = "bad" if health <= 5 else "caution" if health <= 20 else "ok"
        if lvl != "ok":
            verdict = worst(verdict, "bad" if lvl == "bad" else "caution")
            reasons.append({"code": "wear", "level": lvl})
        add(metrics, "life_left", health, lvl, "%")
        break

    for aid, (code, bad_level) in ATA_COUNTERS.items():
        t = table.get(aid)
        if not t:
            continue
        n = int(t["pretty"])
        lvl = "ok" if n == 0 else bad_level
        if lvl == "caution":
            verdict = worst(verdict, "caution")
            reasons.append({"code": code, "level": "caution"})
        elif n == 0 and bad_level == "info":
            lvl = "info"
        add(metrics, code, n, lvl)

    temp = kelvin_to_c(p.get("SmartTemperature"))
    limit = 55 if rotational else 70
    tlvl = "caution" if temp is not None and temp >= limit else "ok"
    if tlvl != "ok":
        verdict = worst(verdict, "caution")
        reasons.append({"code": "temp_high", "level": "caution"})
    add(metrics, "temperature", temp, tlvl, "C", limit=limit)

    for aid, code in ((12, "power_cycles"), (192, "unsafe_shutdowns")):
        t = table.get(aid)
        if t:
            add(metrics, code, int(t["pretty"]))

    secs = p.get("SmartPowerOnSeconds")
    hours = round(secs / 3600) if secs else None
    # 241 / 242 report megabytes in UDisks' pretty value (unit 7)
    written = read = None
    for aid, key in ((241, "w"), (242, "r")):
        t = table.get(aid)
        if t and t["unit"] == 7:
            val = int(t["pretty"]) * 1000 * 1000
            if key == "w":
                written = val
            else:
                read = val
    return {
        "verdict": verdict, "health": health, "temp": temp,
        "power_on_hours": hours, "written": written, "read": read,
        "reasons": reasons, "metrics": metrics,
    }


def collect():
    objs = managed_objects()
    names = block_names(objs)
    drives = []
    for path, ifaces in sorted(objs.items()):
        if IFACE_DRIVE not in ifaces:
            continue
        name = names.get(path)
        if not name:
            continue
        base = props(ifaces[IFACE_DRIVE])
        entry = {
            "name": name,
            "model": (base.get("Model") or "").strip() or name,
            "kind": None,
            "supported": False,
            "verdict": "unknown",
            "health": None, "temp": None, "power_on_hours": None,
            "written": None, "read": None,
            "updated": None, "reasons": [], "metrics": [],
        }
        if IFACE_ATA in ifaces:
            p = props(ifaces[IFACE_ATA])
            entry["kind"] = "ata"
            entry["supported"] = bool(p.get("SmartSupported") and p.get("SmartEnabled"))
            if entry["supported"] and p.get("SmartUpdated"):
                entry.update(ata_health(path, p, bool(base.get("RotationRate", 0) > 0)))
                entry["updated"] = p.get("SmartUpdated")
        elif IFACE_NVME in ifaces:
            p = props(ifaces[IFACE_NVME])
            entry["kind"] = "nvme"
            if p.get("SmartUpdated"):
                entry["supported"] = True
                entry.update(nvme_health(path, p))
                entry["updated"] = p.get("SmartUpdated")
        drives.append(entry)
    drives.sort(key=lambda d: d["name"])
    return {"drives": drives}


if __name__ == "__main__":
    try:
        print(json.dumps(collect()))
    except Exception:  # never break the page: an empty list means "no data"
        print(json.dumps({"drives": []}))
        sys.exit(0)
