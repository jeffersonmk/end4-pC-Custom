#!/usr/bin/env python3
"""Wallpaper Engine Steam Workshop helper for the wallpaper selector.

Prints one JSON document on stdout. Never needs a login, a Steam Web API key or
the Steam client: it reads the public Workshop pages and the folders Steam
already downloaded.

  workshop.py browse [--query TEXT] [--sort trend|recent|popular|updated]
                     [--days N] [--page N] [--tag NAME] [--mature]
  workshop.py library [--mature] [--extra-dir DIR]
                                      Workshop items (downloaded or not) + Wallpaper Engine's own
                                      projects + plain videos in DIR; each item has an "origin"
  workshop.py delete ID [ID...]       delete downloaded item folders (nothing else)
  workshop.py requirements            checklist for the selector

Content rating: browse returns only "Everyone" items unless --mature is given;
library hides "Questionable" and "Mature" ones unless --mature is given. Items
without a rating are treated as not adult.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from typing import NoReturn

APPID = 431960  # Wallpaper Engine
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
RATINGS = ("Everyone", "Questionable", "Mature")
ORIGIN_ORDER = {"workshop": 0, "mine": 1, "folder": 2, "app": 3}
SORTS = {
    "trend": "trend",
    "recent": "mostrecent",
    "popular": "totaluniquesubscribers",
    "updated": "lastupdated",
}
VIDEO_EXT = (".mp4", ".webm", ".mkv", ".mov", ".avi")


def out(obj, code=0) -> NoReturn:
    json.dump(obj, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    sys.exit(code)


# ----------------------------------------------------------------- online --

def fetch(url, data=None, timeout=25):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA, "Accept-Language": "en-US,en;q=0.9"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


def item_from_steam(raw):
    tags = [t.get("tag", "") for t in raw.get("tags", [])]
    rating = next((t for t in tags if t in RATINGS), "")
    resolution = next((t for t in tags if re.fullmatch(r"\d+ x \d+", t)), "")
    genre = [t for t in tags if t not in RATINGS and t not in ("Video", "Wallpaper", "Scene", "Web", "Application", "Approved") and t != resolution]
    try:
        size = int(raw.get("file_size") or 0)
    except ValueError:
        size = 0
    return {
        "id": str(raw.get("publishedfileid", "")),
        "title": raw.get("title", "") or "",
        "preview": raw.get("preview_url", "") or "",
        "rating": rating,
        "resolution": resolution,
        "tags": genre[:6],
        "size": size,
        "subscriptions": int(raw.get("lifetime_subscriptions") or raw.get("subscriptions") or 0),
        "type": "video" if "Video" in tags else ("scene" if "Scene" in tags else ""),
    }


def browse_from_ssr(html):
    m = re.search(r'<script type="application/json" id="valve-ssr-data"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        return None
    query_data = json.loads(json.loads(m.group(1))["renderContext"]["queryData"])
    for q in query_data["queries"]:
        if q["queryHash"].startswith('["workshop_browse"'):
            d = q["state"]["data"]
            return {
                "items": [item_from_steam(r) for r in d.get("results", [])],
                "page": int(d.get("current_page") or 1),
                "totalPages": min(int(d.get("total_pages") or 1), 1000),
                "total": int(d.get("total_count") or 0),
            }
    return None


def browse_from_ids(html):
    """Fallback if Steam changes the page: scrape ids, ask the public details API."""
    ids = list(dict.fromkeys(re.findall(r"sharedfiles/filedetails/\?id=(\d+)", html)))
    if not ids:
        return None
    body = urllib.parse.urlencode(
        [("itemcount", len(ids))] + [(f"publishedfileids[{i}]", x) for i, x in enumerate(ids)]
    ).encode()
    d = json.loads(fetch("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/", data=body))
    items = [item_from_steam(r) for r in d["response"]["publishedfiledetails"] if r.get("result") == 1]
    return {"items": items, "page": 1, "totalPages": 1, "total": len(items)}


def cmd_browse(a):
    params = [("appid", APPID), ("section", "readytouseitems"), ("p", a.page)]
    query = a.query.strip()
    if query:
        params += [("browsesort", "textsearch"), ("searchtext", query)]
    else:
        params += [("browsesort", SORTS.get(a.sort, "trend")), ("days", a.days)]
    required = ["Video"]
    if a.tag:
        required.append(a.tag)
    if not a.mature:
        required.append("Everyone")
    params += [("requiredtags[]", t) for t in required]
    url = "https://steamcommunity.com/workshop/browse/?" + urllib.parse.urlencode(params)
    try:
        html = fetch(url)
    except Exception as e:  # network, 4xx, 5xx
        out({"ok": False, "error": f"Steam Workshop is not reachable: {e}"}, 1)
    try:
        res = browse_from_ssr(html) or browse_from_ids(html)
    except Exception as e:
        out({"ok": False, "error": f"Could not read the Workshop page: {e}"}, 1)
    if res is None:
        out({"ok": False, "error": "Could not read the Workshop page (layout changed?)"}, 1)
    # Belt and braces: the tag filter should already do this, a text search may not.
    if not a.mature:
        res["items"] = [i for i in res["items"] if i["rating"] in ("Everyone", "")]
    res["items"] = [i for i in res["items"] if i["type"] in ("video", "")]
    res["ok"] = True
    out(res)


# ------------------------------------------------------------------ local --

def steam_roots():
    home = os.path.expanduser("~")
    cands = [
        f"{home}/.local/share/Steam",
        f"{home}/.steam/steam",
        f"{home}/.steam/root",
        f"{home}/.var/app/com.valvesoftware.Steam/.local/share/Steam",
    ]
    # Extra Steam roots (colon separated), mostly for testing
    cands = [c for c in os.environ.get("WORKSHOP_STEAM_ROOTS", "").split(":") if c] + cands
    roots = []
    for base in list(cands):
        vdf = os.path.join(base, "steamapps", "libraryfolders.vdf")
        if os.path.isfile(vdf):
            try:
                with open(vdf, encoding="utf-8", errors="replace") as f:
                    cands += re.findall(r'"path"\s+"([^"]+)"', f.read())
            except OSError:
                pass
    for c in cands:
        r = os.path.realpath(c)
        if r not in roots and os.path.isdir(r):
            roots.append(r)
    return roots


def workshop_dirs():
    return [
        os.path.join(r, "steamapps", "workshop", "content", str(APPID))
        for r in steam_roots()
        if os.path.isdir(os.path.join(r, "steamapps", "workshop", "content", str(APPID)))
    ]


def parse_vdf(text):
    """Minimal Valve KeyValues parser (what Steam writes in .acf / .vdf files)."""
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', text)
    pos = 0

    def block():
        nonlocal pos
        d = {}
        while pos < len(tokens):
            key, brace = tokens[pos]
            pos += 1
            if brace == "}":
                return d
            if brace == "{":
                continue
            nkey, nbrace = tokens[pos] if pos < len(tokens) else ("", "")
            if nbrace == "{":
                pos += 1
                d[key] = block()
            else:
                pos += 1
                d[key] = nkey
        return d

    return block()


def read_acf(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return parse_vdf(f.read())
    except OSError:
        return {}


def dir_size(path):
    total = 0
    for root, _dirs, files in os.walk(path):
        for fn in files:
            try:
                total += os.path.getsize(os.path.join(root, fn))
            except OSError:
                pass
    return total


def steam_view():
    """What Steam says about our app: subscribed ids, installed ids, pending updates."""
    subscribed, installed, outdated = set(), {}, set()
    for r in steam_roots():
        acf = read_acf(os.path.join(r, "steamapps", "workshop", f"appworkshop_{APPID}.acf")).get("AppWorkshop", {})
        for wid, d in acf.get("WorkshopItemDetails", {}).items():
            if not isinstance(d, dict):
                continue
            subscribed.add(wid)
            if d.get("manifest") != d.get("latest_manifest"):
                outdated.add(wid)
        for wid, d in acf.get("WorkshopItemsInstalled", {}).items():
            if isinstance(d, dict):
                try:
                    installed[wid] = int(d.get("size") or 0)
                except ValueError:
                    installed[wid] = 0
    return subscribed, installed, outdated


def steam_details(ids):
    """Title, preview and tags for items we only know by id (public API, no key)."""
    found = {}
    ids = list(ids)
    for i in range(0, len(ids), 100):
        chunk = ids[i:i + 100]
        body = urllib.parse.urlencode(
            [("itemcount", len(chunk))] + [(f"publishedfileids[{n}]", x) for n, x in enumerate(chunk)]
        ).encode()
        try:
            d = json.loads(fetch("https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/", data=body, timeout=15))
        except Exception:
            continue
        for r in d.get("response", {}).get("publishedfiledetails", []):
            if r.get("result") == 1:
                found[str(r["publishedfileid"])] = item_from_steam(r)
    return found


def local_item(base, wid, origin="workshop", item_id=None):
    """Read one item folder. Returns None if it has no readable project.json."""
    d = os.path.join(base, wid)
    pj = os.path.join(d, "project.json")
    if not os.path.isfile(pj):
        return None
    try:
        with open(pj, encoding="utf-8-sig", errors="replace") as f:
            p = json.load(f)
    except (OSError, ValueError):
        return None
    kind = str(p.get("type", "")).lower()
    fname = str(p.get("file", ""))
    fpath = os.path.join(d, fname) if fname else ""
    tags = [str(t) for t in p.get("tags", []) if isinstance(t, str)]
    rating = str(p.get("contentrating", "") or "")
    if rating not in RATINGS:
        rating = next((t for t in tags if t in RATINGS), "")
    prev = str(p.get("preview", ""))
    prev_path = os.path.join(d, prev) if prev else ""
    if kind in ("", "none"):
        return None  # templates, not wallpapers
    return {
        "id": item_id or wid,
        "origin": origin,
        "title": str(p.get("title", "")) or wid,
        "type": kind or "unknown",
        "supported": kind == "video" and fname.lower().endswith(VIDEO_EXT) and os.path.isfile(fpath),
        "file": fpath if kind == "video" and os.path.isfile(fpath) else "",
        "preview": prev_path if prev and os.path.isfile(prev_path) else "",
        "rating": rating,
        "tags": [t for t in tags if t not in RATINGS and t != "Approved"][:6],
        "dir": d,
    }


THUMB_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "quickshell", "workshop-thumbs")


def video_thumb(path):
    """One frame of a plain video file, cached. Empty string if ffmpeg is missing or fails."""
    ff = shutil.which("ffmpeg")
    if not ff:
        return ""
    try:
        st = os.stat(path)
    except OSError:
        return ""
    key = re.sub(r"[^A-Za-z0-9]+", "_", f"{path}_{st.st_size}_{int(st.st_mtime)}")[-120:]
    dest = os.path.join(THUMB_DIR, key + ".jpg")
    if os.path.isfile(dest):
        return dest
    os.makedirs(THUMB_DIR, exist_ok=True)
    try:
        subprocess.run([ff, "-y", "-v", "error", "-ss", "1", "-i", path, "-frames:v", "1", "-vf", "scale=480:-2", dest],
                       timeout=12, stdin=subprocess.DEVNULL, check=True)
    except (subprocess.SubprocessError, OSError):
        return ""
    return dest if os.path.isfile(dest) else ""


def wallpaper_engine_items():
    """Projects that ship with / were made in the Wallpaper Engine app (not from the Workshop)."""
    items = []
    for r in steam_roots():
        base = os.path.join(r, "steamapps", "common", "wallpaper_engine", "projects")
        for sub, origin in (("myprojects", "mine"), ("defaultprojects", "app")):
            d = os.path.join(base, sub)
            if not os.path.isdir(d):
                continue
            for name in sorted(os.listdir(d)):
                it = local_item(d, name, origin, f"{origin}:{name}")
                if it:
                    it.update({"downloaded": True, "subscribed": False, "needsUpdate": False, "size": dir_size(it["dir"])})
                    items.append(it)
    return items


def folder_videos(folder, skip_under):
    """Plain video files in a user folder (the 'Live Wallpaper Folder' setting)."""
    items = []
    if not folder or not os.path.isdir(folder):
        return items
    skip = [os.path.realpath(x) + os.sep for x in skip_under]
    for root_, dirs, files in os.walk(folder):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        if root_[len(folder):].count(os.sep) >= 2:
            dirs[:] = []
        if any((os.path.realpath(root_) + os.sep).startswith(sk) for sk in skip):
            dirs[:] = []
            continue
        for fn in sorted(files):
            if not fn.lower().endswith(VIDEO_EXT):
                continue
            fp = os.path.join(root_, fn)
            try:
                size = os.path.getsize(fp)
            except OSError:
                continue
            items.append({
                "id": "folder:" + os.path.relpath(fp, folder),
                "origin": "folder",
                "title": os.path.splitext(fn)[0],
                "type": "video",
                "supported": True,
                "file": fp,
                "preview": video_thumb(fp),
                "rating": "",
                "tags": [],
                "dir": "",
                "downloaded": True,
                "subscribed": False,
                "needsUpdate": False,
                "size": size,
            })
    return items


def cmd_library(a):
    subscribed, installed, outdated = steam_view()
    items, seen = {}, set()
    for base in workshop_dirs():
        for wid in os.listdir(base):
            if not wid.isdigit() or wid in seen:
                continue
            it = local_item(base, wid)
            if it is None:
                continue  # folder without project.json: half-downloaded, shown as pending below
            seen.add(wid)
            it["downloaded"] = True
            it["origin"] = "workshop"
            it["subscribed"] = wid in subscribed
            it["needsUpdate"] = wid in outdated
            it["size"] = installed.get(wid) or dir_size(it["dir"])
            items[wid] = it
    # Subscribed according to Steam, but nothing usable on disk
    pending = [w for w in sorted(subscribed | set(installed)) if w not in items]
    details = steam_details(pending) if pending else {}
    for wid in pending:
        d = details.get(wid, {})
        items[wid] = {
            "id": wid,
            "origin": "workshop",
            "title": d.get("title") or wid,
            "type": d.get("type") or "unknown",
            "supported": d.get("type") == "video",
            "file": "",
            "preview": d.get("preview", ""),
            "rating": d.get("rating", ""),
            "tags": d.get("tags", []),
            "dir": "",
            "downloaded": False,
            "subscribed": True,
            "needsUpdate": wid in outdated,
            "size": d.get("size", 0),
            "resolution": d.get("resolution", ""),
        }
    extras = wallpaper_engine_items()
    if a.extra_dir:
        extras += folder_videos(os.path.expanduser(a.extra_dir), workshop_dirs())
    for it in extras:
        items[it["id"]] = it
    hidden = 0
    out_items = []
    for it in items.values():
        if not a.mature and it["rating"] in ("Questionable", "Mature"):
            hidden += 1
            continue
        out_items.append(it)
    out_items.sort(key=lambda i: (ORIGIN_ORDER.get(i["origin"], 9), not i["downloaded"], i["title"].lower()))
    out({
        "ok": True,
        "items": out_items,
        "hiddenByRating": hidden,
        "steamRunning": steam_running(),
        "dirs": workshop_dirs(),
    })


def cmd_delete(a):
    """Delete downloaded item folders. Only numeric ids, only direct children of the
    Workshop content folder of this app, never through symlinks."""
    bases = {os.path.realpath(b): b for b in workshop_dirs()}
    deleted, failed, freed = [], [], 0
    for wid in a.ids:
        if not wid.isdigit():
            failed.append({"id": wid, "error": "invalid id"})
            continue
        target = None
        for real in bases:
            cand = os.path.join(real, wid)
            if os.path.lexists(cand):
                target = cand
                break
        if target is None:
            failed.append({"id": wid, "error": "not found"})
            continue
        if os.path.islink(target) or not os.path.isdir(target) or os.path.dirname(os.path.realpath(target)) not in bases:
            failed.append({"id": wid, "error": "refused: not a plain folder inside the Workshop content folder"})
            continue
        size = dir_size(target)
        try:
            shutil.rmtree(target)
            deleted.append(wid)
            freed += size
        except OSError as e:
            failed.append({"id": wid, "error": str(e)})
    out({"ok": not failed, "deleted": deleted, "failed": failed, "freed": freed})


def steam_running():
    try:
        for pid in os.listdir("/proc"):
            if pid.isdigit():
                with open(f"/proc/{pid}/comm") as f:
                    if f.read().strip() == "steam":
                        return True
    except OSError:
        pass
    return False


def cmd_requirements(_a):
    roots = steam_roots()
    manifests = [r for r in roots if os.path.isfile(os.path.join(r, "steamapps", f"appmanifest_{APPID}.acf"))]
    wdirs = workshop_dirs()
    try:
        urllib.request.urlopen(urllib.request.Request("https://steamcommunity.com/", headers={"User-Agent": UA}), timeout=6)
        net = True
    except Exception:
        net = False
    checks = [
        ("steam", "Steam is installed", bool(roots), "required",
         "Install Steam (sudo -S -p '' pacman -S steam) and sign in once."),
        ("we", "Wallpaper Engine is installed in Steam", bool(manifests), "recommended",
         "Install Wallpaper Engine from your Steam library (you can leave it closed). Steam may not download its Workshop items otherwise."),
        ("running", "Steam is running", steam_running(), "recommended",
         "Open Steam: it does the downloading when you subscribe."),
        ("workshop", "Workshop folder exists (something was downloaded)", bool(wdirs), "recommended",
         "It appears after Steam downloads your first Wallpaper Engine Workshop item."),
        ("mpvpaper", "mpvpaper (plays video wallpapers)", shutil.which("mpvpaper") is not None, "required",
         "sudo pacman -S mpvpaper  (or yay -S mpvpaper)"),
        ("ffmpeg", "ffmpeg (makes the thumbnails and colors)", shutil.which("ffmpeg") is not None, "required",
         "sudo pacman -S ffmpeg"),
        ("xdg-open", "xdg-open (opens Steam links)", shutil.which("xdg-open") is not None, "required",
         "sudo pacman -S xdg-utils"),
        ("net", "Steam Workshop is reachable", net, "required",
         "Check your internet connection. Browsing online needs it; Library works offline."),
    ]
    out({
        "ok": True,
        "checks": [{"id": i, "label": l, "ok": ok, "level": lv, "hint": h} for i, l, ok, lv, h in checks],
        "requiredFailing": sum(1 for _i, _l, ok, lv, _h in checks if not ok and lv == "required"),
        "videoOnly": True,
    })


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("browse")
    b.add_argument("--query", default="")
    b.add_argument("--sort", default="trend")
    b.add_argument("--days", type=int, default=7)
    b.add_argument("--page", type=int, default=1)
    b.add_argument("--tag", default="")
    b.add_argument("--mature", action="store_true")
    b.set_defaults(fn=cmd_browse)
    lib = sub.add_parser("library")
    lib.add_argument("--mature", action="store_true")
    lib.add_argument("--extra-dir", default="", help="folder with your own video wallpapers")
    lib.set_defaults(fn=cmd_library)
    d = sub.add_parser("delete")
    d.add_argument("ids", nargs="+")
    d.set_defaults(fn=cmd_delete)
    r = sub.add_parser("requirements")
    r.set_defaults(fn=cmd_requirements)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
