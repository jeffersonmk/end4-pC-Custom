#!/usr/bin/env python3
"""Find a high-resolution album cover.

Usage: hd_cover.py ARTIST ALBUM [TITLE]
Prints an image URL (>= 1000px when available) or nothing.

With an album: iTunes (1000x1000) -> Deezer (cover_xl) -> MusicBrainz/Cover Art Archive (1200px).
Without an album (YouTube uploads, singles): the same sources are searched by song title.
Results are cached on disk so each album/song is looked up once; misses are retried after 7 days.
"""
import hashlib
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

CACHE_DIR = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                         "quickshell", "hdcovers")
MISS_TTL = 7 * 24 * 3600
UA = "end4-pC-Custom/1.0 (https://github.com/jeffersonmk/end4-pC-Custom)"
ARTIST_SPLIT = re.compile(r"\s*(?:,|;|&| / | x | feat\.? | ft\.? | featuring | with )\s*", re.I)
TITLE_NOISE = re.compile(
    r"\s*[\(\[][^\)\]]*(official|video|audio|lyric|visuali[sz]er|remaster|live|hd|hq|4k|explicit|clean|feat\.?|ft\.?)[^\)\]]*[\)\]]",
    re.I)


def norm(s: str) -> str:
    s = s.lower()
    s = re.sub(r"[\(\[].*?[\)\]]", " ", s)  # (Deluxe Edition), [Remastered]...
    s = re.sub(r"\b(deluxe|edition|remaster(ed)?|expanded|anniversary|version|ep|single)\b", " ", s)
    s = re.sub(r"[^\w\s]", " ", s)
    return " ".join(s.split())


def same(a: str, b: str) -> bool:
    a, b = norm(a), norm(b)
    return bool(a and b) and (a == b or a in b or b in a)


def clean_title(title: str, artist: str) -> str:
    t = TITLE_NOISE.sub("", title)
    t = re.sub(r"\s+(feat\.?|ft\.?|featuring)\s.*$", "", t, flags=re.I)
    # "Artist - Song" (common on YouTube)
    if " - " in t:
        left, right = t.split(" - ", 1)
        if same(left, artist):
            t = right
    return t.strip()


def get_json(url: str):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read().decode())
    except Exception:
        return None


def resolve(url: str) -> str:
    """Return the final URL if the image exists (follows redirects), else ''."""
    req = urllib.request.Request(url, method="HEAD", headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.geturl() if r.status == 200 else ""
    except Exception:
        return ""


def itunes_big(art: str) -> str:
    return re.sub(r"/\d+x\d+bb\.(jpg|png)$", r"/1000x1000bb.\1", art) if art else ""


# ── Album lookups ──
def itunes(artist: str, album: str) -> str:
    q = urllib.parse.urlencode({"term": f"{artist} {norm(album)}", "entity": "album", "limit": 25})
    data = get_json(f"https://itunes.apple.com/search?{q}") or {}
    for r in data.get("results", []):
        if same(r.get("collectionName", ""), album) and same(r.get("artistName", ""), artist):
            return itunes_big(r.get("artworkUrl100") or "")
    return ""


def deezer(artist: str, album: str) -> str:
    q = urllib.parse.urlencode({"q": f'artist:"{artist}" album:"{norm(album)}"'})
    data = get_json(f"https://api.deezer.com/search/album?{q}") or {}
    for r in data.get("data", []):
        if same(r.get("title", ""), album) and same((r.get("artist") or {}).get("name", ""), artist):
            return r.get("cover_xl") or r.get("cover_big") or ""
    return ""


def caa(mbid: str, kind: str = "release-group") -> str:
    # Keep the stable coverartarchive.org link (it redirects to a changing archive.org mirror)
    url = f"https://coverartarchive.org/{kind}/{mbid}/front-1200"
    return url if resolve(url) else ""


def mb_query(s: str) -> str:
    return re.sub(r'([+\-&|!(){}\[\]^"~*?:\\/])', r"\\\1", s)


def musicbrainz(artist: str, album: str) -> str:
    q = f'releasegroup:"{mb_query(norm(album))}" AND artist:"{mb_query(artist)}"'
    data = get_json("https://musicbrainz.org/ws/2/release-group/?" +
                    urllib.parse.urlencode({"query": q, "fmt": "json", "limit": 5})) or {}
    for r in data.get("release-groups", []):
        credit = " ".join(c.get("name", "") for c in r.get("artist-credit", []))
        if r.get("score", 0) >= 80 and same(r.get("title", ""), album) and same(credit, artist):
            url = caa(r["id"])
            if url:
                return url
            time.sleep(1)  # MusicBrainz asks for max 1 request/second
    return ""


# ── Song lookups (no album known) ──
def itunes_song(artist: str, title: str) -> str:
    q = urllib.parse.urlencode({"term": f"{artist} {title}", "entity": "song", "limit": 25})
    data = get_json(f"https://itunes.apple.com/search?{q}") or {}
    for r in data.get("results", []):
        if same(r.get("trackName", ""), title) and same(r.get("artistName", ""), artist):
            return itunes_big(r.get("artworkUrl100") or "")
    return ""


def deezer_song(artist: str, title: str) -> str:
    q = urllib.parse.urlencode({"q": f'artist:"{artist}" track:"{title}"'})
    data = get_json(f"https://api.deezer.com/search/track?{q}") or {}
    for r in data.get("data", []):
        if same(r.get("title", ""), title) and same((r.get("artist") or {}).get("name", ""), artist):
            alb = r.get("album") or {}
            return alb.get("cover_xl") or alb.get("cover_big") or ""
    return ""


def musicbrainz_song(artist: str, title: str) -> str:
    q = f'recording:"{mb_query(title)}" AND artist:"{mb_query(artist)}"'
    data = get_json("https://musicbrainz.org/ws/2/recording/?" +
                    urllib.parse.urlencode({"query": q, "fmt": "json", "limit": 5})) or {}
    for r in data.get("recordings", []):
        credit = " ".join(c.get("name", "") for c in r.get("artist-credit", []))
        if r.get("score", 0) < 80 or not same(r.get("title", ""), title) or not same(credit, artist):
            continue
        for rel in r.get("releases", [])[:3]:
            rg = (rel.get("release-group") or {}).get("id")
            if rg:
                url = caa(rg)
                if url:
                    return url
                time.sleep(1)
    return ""


def main():
    if len(sys.argv) < 3:
        return
    # YouTube channel names: "Linkin Park - Topic", "LinkinParkVEVO"
    channel = re.sub(r"\s*-\s*Topic$|VEVO$", "", sys.argv[1].strip(), flags=re.I)
    artist = ARTIST_SPLIT.split(channel)[0]
    album = sys.argv[2].strip()
    raw_title = sys.argv[3].strip() if len(sys.argv) > 3 else ""
    title = ""
    if album:
        key = f"{artist}\x1f{album}"
    else:
        title = clean_title(raw_title, artist)
        key = f"{artist}\x1ftrack:{title}"
    if not artist or not (album or title):
        return

    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, hashlib.md5(key.lower().encode()).hexdigest())
    try:
        with open(path) as f:
            cached = json.load(f)
        if cached.get("url") or time.time() - cached.get("time", 0) < MISS_TTL:
            print(cached.get("url", ""))
            return
    except Exception:
        pass

    if album:
        url = itunes(artist, album) or deezer(artist, album) or musicbrainz(artist, album)
    else:
        tries = [(artist, title)]
        # YouTube uploads by a channel that isn't the artist: "Artist - Song (Official Video)"
        t = TITLE_NOISE.sub("", raw_title)
        if " - " in t:
            left, right = (x.strip() for x in t.split(" - ", 1))
            if left and right and not same(left, artist):
                tries.append((ARTIST_SPLIT.split(left)[0], clean_title(right, left)))
        url = ""
        for a, t in tries:
            url = itunes_song(a, t) or deezer_song(a, t)
            if url:
                break
        if not url:
            for a, t in tries:
                url = musicbrainz_song(a, t)
                if url:
                    break
    try:
        with open(path, "w") as f:
            json.dump({"time": time.time(), "url": url}, f)
    except Exception:
        pass
    print(url)


if __name__ == "__main__":
    main()
