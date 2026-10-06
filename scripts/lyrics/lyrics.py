#!/usr/bin/env python3
"""Fetch time-synced lyrics from lrclib.net.

Usage: lyrics.py TITLE ARTIST DURATION_SECONDS [ALBUM] [--refresh]
Prints "t§text§t§text§...§ok" (synced), "...§plain" (unsynced lyrics with estimated
times), "not_found" or "no_info". --refresh ignores the cache.

Search strategy (stops at the first synced match):
  1. exact lookup with every artist variant (full string, then the main artist
     when the field lists several: "Nile, Karl Sanders" -> "Nile")
  2. searches by track + artist, then free text
Among the results, the synced version whose length is closest to the playing
track wins, so the lines line up with the version that is actually playing.
When no synced version exists, plain lyrics are returned instead, spread evenly over
the track so they scroll along. Results (including "not found") are cached on disk.
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://lrclib.net/api"
UA = "end4-pC-Custom lyrics (https://github.com/jeffersonmk/end4-pC-Custom)"
CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                         "quickshell", "lyrics")
NOT_FOUND_TTL = 3 * 24 * 3600  # retry songs without lyrics after a few days
MAX_DURATION_DIFF = 12          # seconds; beyond this it's probably another version

ARTIST_SPLIT = re.compile(r"\s*(?:,|;|&| / | x | feat\.? | ft\.? | featuring | with )\s*", re.I)
TITLE_NOISE = [
    re.compile(r"\s*[\(\[](?:feat|ft)\.?\s[^\)\]]*[\)\]]", re.I),
    re.compile(r"\s*[\(\[][^\)\]]*(?:official|video|audio|lyric|visuali[sz]er|remaster|live|explicit|clean|hd|hq|4k|mv)[^\)\]]*[\)\]]", re.I),
    re.compile(r"\s+-\s+(?:\d{4}\s+)?remaster(?:ed)?(?:\s+\d{4})?(?:\s+version)?$", re.I),
    re.compile(r"\s+(?:feat|ft)\.?\s.*$", re.I),
    re.compile(r"\s*\|.*$"),
]
TAG = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")
OFFSET = re.compile(r"\[offset:\s*([+-]?\d+)\]", re.I)


def norm(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[\(\[].*?[\)\]]", " ", s)
    s = re.sub(r"[^\w\s]", " ", s)
    return " ".join(s.split())


def clean_title(title: str) -> str:
    t = title
    for rx in TITLE_NOISE:
        t = rx.sub("", t)
    return t.strip() or title.strip()


def artist_variants(artist: str) -> list:
    out = []
    for a in [artist.strip(), ARTIST_SPLIT.split(artist.strip())[0]]:
        if a and a.lower() not in [x.lower() for x in out]:
            out.append(a)
    return out


def parse_lrc(text: str) -> list:
    offset = 0.0
    m = OFFSET.search(text)
    if m:
        offset = int(m.group(1)) / 1000.0
    lines = []
    for raw in text.splitlines():
        tags = TAG.findall(raw)
        if not tags:
            continue
        words = TAG.sub("", raw).strip()
        for mins, secs in tags:
            t = int(mins) * 60 + float(secs.replace(":", ".")) - offset
            lines.append({"time": max(0.0, t), "text": words})
    lines.sort(key=lambda x: x["time"])
    return lines


def http_json(path: str, params: dict):
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=12) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 500, 502, 503, 504) and attempt < 2:
                time.sleep(1.5 * (attempt + 1))  # lrclib often answers "server busy"
                continue
            return None
        except Exception:
            if attempt < 2:
                time.sleep(1)
                continue
            return None
    return None


def matches(d: dict, titles: list, artists: list) -> bool:
    r_title = norm(d.get("trackName") or "")
    r_artist = norm(d.get("artistName") or "")
    if not r_title or not r_artist:
        return False
    title_ok = any(t and (t == r_title or t in r_title or r_title in t) for t in titles)
    artist_ok = any(a and (a in r_artist or r_artist in a) for a in artists)
    return title_ok and artist_ok


def pick(results: list, titles: list, artists: list, duration: float, field: str = "syncedLyrics"):
    """Result with lyrics in `field` closest in length to the playing track."""
    best, best_diff = None, 0.0
    for d in results:
        if not isinstance(d, dict) or not d.get(field) or not matches(d, titles, artists):
            continue
        diff = abs((d.get("duration") or 0) - duration) if duration > 0 else 0
        if best is None or diff < best_diff:
            best, best_diff = d, diff
    if best is None:
        return None
    # Wrong-length versions would be out of sync; only accept them when nothing closer exists
    # and the track length is unknown. (Plain lyrics have no timing, any version will do.)
    if field == "syncedLyrics" and duration > 0 and best_diff > MAX_DURATION_DIFF:
        return None
    return best


def spread_plain(text: str, duration: float) -> list:
    """Give unsynced lyrics estimated times so they scroll along with the song."""
    words = [l.strip() for l in text.splitlines()]
    while words and not words[0]:
        words.pop(0)
    while words and not words[-1]:
        words.pop()
    if not words:
        return []
    n = len(words)
    if duration > 0:
        start, end = duration * 0.06, duration * 0.94
        step = (end - start) / max(n, 1)
    else:
        start, step = 5.0, 3.5
    return [{"time": round(start + i * step, 3), "text": w} for i, w in enumerate(words)]


def fetch(title: str, artist: str, duration: float, album: str):
    """Returns (lines, plain)."""
    titles_raw = [title.strip()]
    cleaned = clean_title(title)
    if cleaned.lower() != title.strip().lower():
        titles_raw.append(cleaned)
    # YouTube-style "Artist - Title"
    if " - " in cleaned:
        left, right = cleaned.split(" - ", 1)
        if norm(left) in norm(artist) or norm(artist) in norm(left):
            titles_raw.append(right.strip())
    artists_raw = artist_variants(artist)
    titles = [norm(t) for t in titles_raw]
    artists = [norm(a) for a in artists_raw]

    # 1. exact lookups (fast path, lrclib matches length within ~2s)
    exact = []
    if duration > 0:
        for t in titles_raw:
            for a in artists_raw:
                params = {"track_name": t, "artist_name": a, "duration": int(round(duration))}
                if album:
                    params["album_name"] = album
                d = http_json("get", params)
                if isinstance(d, dict) and pick([d], titles, artists, duration):
                    return parse_lrc(d["syncedLyrics"]), False
                if isinstance(d, dict):
                    exact.append(d)

    # 2. searches; pool every candidate and pick the closest synced version
    pool = []
    seen = set()
    queries = [{"track_name": t, "artist_name": a} for t in titles_raw for a in artists_raw]
    queries += [{"q": f"{t} {artists_raw[-1]}"} for t in titles_raw]
    for q in queries:
        res = http_json("search", q)
        if isinstance(res, list):
            for d in res:
                if d.get("id") not in seen:
                    seen.add(d.get("id"))
                    pool.append(d)
        best = pick(pool, titles, artists, duration)
        if best:
            return parse_lrc(best["syncedLyrics"]), False

    # 3. no synced version anywhere: fall back to plain lyrics
    best = pick(exact + pool, titles, artists, duration, "plainLyrics")
    if best:
        lines = spread_plain(best["plainLyrics"], duration)
        if lines:
            return lines, True
    return [], False


def cache_path(title, artist, duration, album) -> str:
    key = f"{title}\x1f{artist}\x1f{int(round(duration))}\x1f{album}".lower()
    return os.path.join(CACHE_DIR, hashlib.md5(key.encode()).hexdigest() + ".json")


def emit(lines: list, plain: bool = False):
    if not lines:
        print("not_found", flush=True)
        return
    parts = []
    for line in lines:
        parts.append(f"{line['time']:.3f}")
        parts.append(line["text"].replace("§", ""))
    parts.append("plain" if plain else "ok")
    print("§".join(parts), flush=True)


def main():
    refresh = "--refresh" in sys.argv
    sys.argv = [a for a in sys.argv if a != "--refresh"]
    if len(sys.argv) < 4:
        print("no_info", flush=True)
        return
    title, artist = sys.argv[1].strip(), sys.argv[2].strip()
    try:
        duration = float(sys.argv[3])
    except ValueError:
        duration = 0.0
    album = sys.argv[4].strip() if len(sys.argv) > 4 else ""
    if not title or not artist:
        print("no_info", flush=True)
        return

    path = cache_path(title, artist, duration, album)
    try:
        with open(path) as f:
            cached = json.load(f)
        age = time.time() - cached.get("time", 0)
        # Synced lyrics never expire; plain ones and misses are retried later (a synced
        # version may be added to lrclib)
        fresh = (cached.get("lines") and not cached.get("plain")) or age < NOT_FOUND_TTL
        if fresh and not refresh:
            emit(cached.get("lines") or [], cached.get("plain", False))
            return
    except Exception:
        pass

    lines, plain = fetch(title, artist, duration, album)
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(path, "w") as f:
            json.dump({"time": time.time(), "lines": lines, "plain": plain}, f)
    except Exception:
        pass
    emit(lines, plain)


if __name__ == "__main__":
    main()
