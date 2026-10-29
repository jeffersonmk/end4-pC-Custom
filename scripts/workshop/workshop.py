#!/usr/bin/env python3
"""Wallpaper Engine Steam Workshop helper for the wallpaper selector.

Prints one JSON document on stdout. Never needs a login, a Steam Web API key or
the Steam client: it reads the public Workshop pages and the folders Steam
already downloaded.

  workshop.py browse [--query TEXT] [--sort trend|recent|popular|updated]
                     [--days N] [--page N] [--tag NAME] [--mature]
  workshop.py local  [--mature]
  workshop.py status

Content rating: unless --mature is given, only items rated "Everyone" are
returned. With --mature, "Questionable" and "Mature" items are included too.
"""
import argparse
import json
import os
import re
import sys
import urllib.parse
import urllib.request
from typing import NoReturn

APPID = 431960  # Wallpaper Engine
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
RATINGS = ("Everyone", "Questionable", "Mature")
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


def cmd_local(a):
    items, skipped = [], {"scene": 0, "web": 0, "application": 0, "other": 0, "rating": 0}
    for base in workshop_dirs():
        for wid in sorted(os.listdir(base)):
            d = os.path.join(base, wid)
            pj = os.path.join(d, "project.json")
            if not os.path.isfile(pj):
                continue
            try:
                with open(pj, encoding="utf-8-sig", errors="replace") as f:
                    p = json.load(f)
            except (OSError, ValueError):
                continue
            kind = str(p.get("type", "")).lower()
            fname = str(p.get("file", ""))
            fpath = os.path.join(d, fname)
            if kind != "video" or not fname.lower().endswith(VIDEO_EXT) or not os.path.isfile(fpath):
                skipped[kind if kind in skipped else "other"] += 1
                continue
            rating = str(p.get("contentrating", "") or "")
            tags = [str(t) for t in p.get("tags", []) if isinstance(t, str)]
            if not rating:
                rating = next((t for t in tags if t in RATINGS), "Everyone")
            if not a.mature and rating in ("Questionable", "Mature"):
                skipped["rating"] += 1
                continue
            prev = str(p.get("preview", ""))
            prev_path = os.path.join(d, prev) if prev else ""
            items.append({
                "id": wid,
                "title": str(p.get("title", wid)),
                "file": fpath,
                "preview": prev_path if prev and os.path.isfile(prev_path) else "",
                "rating": rating,
                "tags": [t for t in tags if t not in RATINGS][:6],
            })
    items.sort(key=lambda i: i["title"].lower())
    out({"ok": True, "items": items, "skipped": skipped, "dirs": workshop_dirs()})


def cmd_status(_a):
    out({"ok": True, "steamRoots": steam_roots(), "workshopDirs": workshop_dirs()})


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
    l = sub.add_parser("local")
    l.add_argument("--mature", action="store_true")
    l.set_defaults(fn=cmd_local)
    s = sub.add_parser("status")
    s.set_defaults(fn=cmd_status)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
