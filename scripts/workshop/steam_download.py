#!/usr/bin/env python3
"""Download Wallpaper Engine Workshop items through the Steam client (Steamworks API).

Asks the Steam client that is already running and signed in to download the
wallpapers you are subscribed to: the same request Wallpaper Engine makes, and
the only one that also fetches items whose files were deleted (Steam keeps
reporting them as installed, so it never downloads them again by itself).

It uses Valve's redistributable libsteam_api.so. Valve only ships it in the
partner SDK, so it is fetched once from the Steamworks.NET repository at a fixed
commit and checked against a fixed SHA-256 before every use; a different file is
refused. It lives in ~/.local/share/quickshell/steamworks, never in this repo.

No password or token is read: the library only talks to the local Steam client.
While it runs, Steam shows you as "playing Wallpaper Engine" (app 431960).

  steam_download.py status              -> {"ok", "installed", "steamRunning"}
  steam_download.py setup               -> fetch + verify the library
  steam_download.py download --all      -> every subscribed item missing on disk
  steam_download.py download <id>...    -> only these (must be subscribed)

`download` prints JSON lines: {"event":"start"|"progress"|"done"|"error", ...}.
"""

import ctypes as C
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request

APPID = 431960
LIB_URL = ("https://raw.githubusercontent.com/rlabrecque/Steamworks.NET/"
           "ba71581f1ed7349e8d0f17ddc6f135dd3bc8a6a3/com.rlabrecque.steamworks.net/Plugins/libsteam_api.so")
LIB_SHA256 = "eb2dd015b84177cf4f4326fe578aab375fd8931bbbd719c7492420d9777007fe"  # Steamworks SDK 1.65a, x86_64
LIB_DIR = os.path.join(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")), "quickshell", "steamworks")
LIB_PATH = os.path.join(LIB_DIR, "libsteam_api.so")

STATE_SUBSCRIBED = 1
STATE_NEEDS_UPDATE = 8
STATE_DOWNLOADING = 16
STATE_PENDING = 32

STALL_SECONDS = 180      # give up on what is left when nothing moves for this long
MAX_SECONDS = 4 * 3600   # hard cap for one run


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def lib_ok():
    try:
        return os.path.isfile(LIB_PATH) and not os.path.islink(LIB_PATH) and sha256(LIB_PATH) == LIB_SHA256
    except OSError:
        return False


def steam_running():
    try:
        return subprocess.run(["pgrep", "-x", "steam"], capture_output=True).returncode == 0
    except OSError:
        return False


def cmd_status():
    emit({"ok": True, "installed": lib_ok(), "steamRunning": steam_running(), "path": LIB_PATH})


def cmd_setup():
    if lib_ok():
        emit({"ok": True, "installed": True, "already": True})
        return 0
    os.makedirs(LIB_DIR, mode=0o700, exist_ok=True)
    part = LIB_PATH + ".part"
    try:
        req = urllib.request.Request(LIB_URL, headers={"User-Agent": "end4-pC-Custom workshop"})
        with urllib.request.urlopen(req, timeout=60) as r, open(part, "wb") as f:
            f.write(r.read(4 << 20))  # the file is ~380 KB
        got = sha256(part)
        if got != LIB_SHA256:
            os.unlink(part)
            emit({"ok": False, "error": f"Downloaded file does not match the expected checksum ({got[:12]}...), refused"})
            return 1
        os.chmod(part, 0o644)
        os.replace(part, LIB_PATH)
    except Exception as e:
        try:
            os.unlink(part)
        except OSError:
            pass
        emit({"ok": False, "error": f"Could not download the Steamworks library: {e}"})
        return 1
    emit({"ok": True, "installed": True})
    return 0


class Steam:
    def __init__(self):
        if not lib_ok():  # checked right before loading, every time
            raise RuntimeError("The Steamworks library is missing or was changed. Run setup again.")
        os.environ["SteamAppId"] = str(APPID)
        os.environ["SteamGameId"] = str(APPID)
        lib = C.CDLL(LIB_PATH)
        lib.SteamAPI_InitFlat.restype = C.c_int
        lib.SteamAPI_InitFlat.argtypes = [C.c_char_p]
        err = C.create_string_buffer(1024)
        res = lib.SteamAPI_InitFlat(err)
        if res != 0:
            msg = err.value.decode("utf-8", "replace") or f"code {res}"
            raise RuntimeError(f"Steam refused the connection ({msg}). Is Steam open and signed in?")
        self.lib = lib

        def fn(name, res, args):
            f = getattr(lib, "SteamAPI_ISteamUGC_" + name)
            f.restype = res
            f.argtypes = [C.c_void_p] + args
            return f

        lib.SteamAPI_SteamUGC_v021.restype = C.c_void_p
        self.ugc = C.c_void_p(lib.SteamAPI_SteamUGC_v021())
        if not self.ugc.value:
            self.close()
            raise RuntimeError("Steam Workshop interface not available")
        self._num = fn("GetNumSubscribedItems", C.c_uint32, [C.c_bool])
        self._subs = fn("GetSubscribedItems", C.c_uint32, [C.POINTER(C.c_uint64), C.c_uint32, C.c_bool])
        self._state = fn("GetItemState", C.c_uint32, [C.c_uint64])
        self._dl = fn("DownloadItem", C.c_bool, [C.c_uint64, C.c_bool])
        self._dlinfo = fn("GetItemDownloadInfo", C.c_bool, [C.c_uint64, C.POINTER(C.c_uint64), C.POINTER(C.c_uint64)])
        self._install = fn("GetItemInstallInfo", C.c_bool,
                           [C.c_uint64, C.POINTER(C.c_uint64), C.c_char_p, C.c_uint32, C.POINTER(C.c_uint32)])

    def subscribed(self):
        n = self._num(self.ugc, False)
        arr = (C.c_uint64 * max(n, 1))()
        got = self._subs(self.ugc, arr, n, False) if n else 0
        return [int(x) for x in arr[:got]]

    def state(self, wid):
        return self._state(self.ugc, wid)

    def folder(self, wid):
        size, ts = C.c_uint64(), C.c_uint32()
        buf = C.create_string_buffer(4096)
        if self._install(self.ugc, wid, C.byref(size), buf, 4096, C.byref(ts)):
            return buf.value.decode("utf-8", "replace")
        return ""

    def on_disk(self, wid):
        folder = self.folder(wid)
        return bool(folder) and os.path.isfile(os.path.join(folder, "project.json"))

    def download(self, wid):
        return self._dl(self.ugc, wid, True)

    def progress(self, wid):
        done, total = C.c_uint64(), C.c_uint64()
        if self._dlinfo(self.ugc, wid, C.byref(done), C.byref(total)):
            return done.value, total.value
        return 0, 0

    def pump(self):
        self.lib.SteamAPI_RunCallbacks()

    def close(self):
        try:
            self.lib.SteamAPI_Shutdown()
        except Exception:
            pass

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def cmd_download(ids, everything):
    if not steam_running():
        emit({"event": "error", "error": "Steam is not running. Open Steam and try again."})
        return 1
    try:
        steam = Steam()
    except Exception as e:
        emit({"event": "error", "error": str(e)})
        return 1

    stop = {"now": False}
    signal.signal(signal.SIGTERM, lambda *_: stop.update(now=True))
    signal.signal(signal.SIGINT, lambda *_: stop.update(now=True))

    with steam:
        subscribed = set(steam.subscribed())
        if everything:
            wanted = sorted(subscribed)
        else:
            wanted = [int(i) for i in ids if i.isdigit() and int(i) in subscribed]
            skipped = [i for i in ids if not (i.isdigit() and int(i) in subscribed)]
            if skipped:
                emit({"event": "warning", "error": "Not subscribed, skipped", "ids": skipped})
        # Missing files (whatever Steam claims), or an update waiting
        todo = [w for w in wanted if not steam.on_disk(w) or steam.state(w) & STATE_NEEDS_UPDATE]
        emit({"event": "start", "total": len(todo), "subscribed": len(subscribed), "ids": [str(w) for w in todo]})
        if not todo:
            emit({"event": "done", "downloaded": [], "failed": [], "cancelled": False})
            return 0

        failed = []
        for w in todo:
            if not steam.download(w):
                failed.append(w)
        left = [w for w in todo if w not in failed]
        done = []
        begin = last_move = time.monotonic()
        last_bytes = -1
        while left and not stop["now"]:
            steam.pump()
            time.sleep(0.5)
            got, total, current = 0, 0, ""
            for w in list(left):
                st = steam.state(w)
                if steam.on_disk(w) and not st & (STATE_DOWNLOADING | STATE_PENDING | STATE_NEEDS_UPDATE):
                    left.remove(w)
                    done.append(w)
                    continue
                d, t = steam.progress(w)
                got += d
                total += t
                if st & STATE_DOWNLOADING and not current:
                    current = str(w)
            moved = got + len(done) * (1 << 40)
            if moved != last_bytes:
                last_bytes, last_move = moved, time.monotonic()
            emit({"event": "progress", "done": len(done), "total": len(todo), "bytes": got,
                  "totalBytes": total, "current": current})
            now = time.monotonic()
            if now - last_move > STALL_SECONDS or now - begin > MAX_SECONDS:
                break
        failed += left
        emit({"event": "done", "downloaded": [str(w) for w in done], "failed": [str(w) for w in failed],
              "cancelled": stop["now"]})
    return 0 if not failed else 2


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    cmd, rest = args[0], args[1:]
    if cmd == "status":
        cmd_status()
        return 0
    if cmd == "setup":
        return cmd_setup()
    if cmd == "download":
        everything = "--all" in rest
        ids = [a for a in rest if a != "--all"]
        if not everything and not ids:
            emit({"event": "error", "error": "Nothing to download"})
            return 2
        return cmd_download(ids, everything)
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
