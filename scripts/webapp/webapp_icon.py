#!/usr/bin/env python3
"""Themed icons for webapps.

  webapp_icon.py candidates HOST [NAME]   -> icon names a theme may provide, one per line
  webapp_icon.py pick THEME NAME...       -> first name the theme (or a theme it inherits,
                                             except hicolor) provides; empty if none

Webapps use the theme's icon when it has one (Papirus has whatsapp, youtube-music,
discord...) and fall back to the site's own icon otherwise.
"""
import importlib.util
import os
import re
import sys

sys.dont_write_bytecode = True  # don't leave __pycache__ in the scripts dir

# Sites whose app icon name isn't derivable from the domain
KNOWN = {
    "music.youtube.com": "youtube-music",
    "web.whatsapp.com": "whatsapp",
    "web.telegram.org": "telegram",
    "mail.google.com": "gmail",
    "calendar.google.com": "google-calendar",
    "drive.google.com": "google-drive",
    "docs.google.com": "google-docs",
    "sheets.google.com": "google-sheets",
    "slides.google.com": "google-slides",
    "keep.google.com": "google-keep",
    "meet.google.com": "google-meet",
    "photos.google.com": "google-photos",
    "messages.google.com": "google-messages",
    "maps.google.com": "google-maps",
    "translate.google.com": "google-translate",
    "gemini.google.com": "google-gemini",
    "chat.openai.com": "chatgpt",
    "chatgpt.com": "chatgpt",
    "claude.ai": "claude",
    "x.com": "twitter",
    "open.spotify.com": "spotify",
    "teams.microsoft.com": "teams",
    "outlook.live.com": "ms-outlook",
    "outlook.office.com": "ms-outlook",
    "app.slack.com": "slack",
    "web.skype.com": "skype",
    "mega.nz": "mega",
    "duck.ai": "duckduckgo",
    "duckduckgo.com": "duckduckgo",
    "primevideo.com": "amazon-prime-video",
    "tv.apple.com": "apple-tv",
    "music.apple.com": "apple-music",
}

SKIP_SUBDOMAINS = {"www", "web", "app", "m", "open", "my"}


def candidates(host, name=""):
    host = (host or "").lower().strip(".")
    out = []

    def add(n):
        n = re.sub(r"[^a-z0-9.+-]+", "-", n.lower()).strip("-")
        if n and n not in out:
            out.append(n)

    bare = re.sub(r"^www\.", "", host)
    for h in (host, bare):
        if h in KNOWN:
            add(KNOWN[h])

    parts = bare.split(".")
    if len(parts) >= 3 and len(parts[-1]) == 2 and parts[-2] in ("co", "com", "org", "net", "gov", "edu", "ac"):
        label, subs = parts[-3], parts[:-3]
    elif len(parts) >= 2:
        label, subs = parts[-2], parts[:-2]
    else:
        label, subs = bare, []
    sub = "-".join(s for s in subs if s not in SKIP_SUBDOMAINS)

    words = re.findall(r"[a-z0-9]+", (name or "").lower())
    if 0 < len(words) <= 3:
        add("-".join(words))
    if sub:
        add(f"{label}-{sub}")
        add(f"{sub}-{label}")
    add(label)
    if 0 < len(words) <= 3:
        add("".join(words))
    return out


def load_resolver():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icon-resolve.py")
    spec = importlib.util.spec_from_file_location("icon_resolve", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def pick(theme, names):
    if not theme or theme == "hicolor":
        return ""
    r = load_resolver()
    chain = [t for t in r.theme_chain(theme) if t != "hicolor"]
    themes = [r.load_theme(t)[0] for t in chain]
    for name in names:
        for entries in themes:
            if r.lookup_in_theme(entries, name):
                return name
    return ""


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "candidates":
        print("\n".join(candidates(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")))
    elif len(sys.argv) >= 3 and sys.argv[1] == "pick":
        print(pick(sys.argv[2], sys.argv[3:]))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
