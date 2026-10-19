#!/usr/bin/env python3
"""Print the MEGA (MEGAcmd) account state as one JSON object for the bar's Cloud widget.

  {"installed": bool, "loggedIn": bool, "state": "synced|syncing|error|offline|missing",
   "used": bytes, "total": bytes, "syncs": [...], "uploads": n, "downloads": n, "percent": 0-100}

Only runs read-only MEGAcmd commands (whoami, df, sync, transfers --summary); never logs in
and never touches credentials. Login is done by the user: `mega-login <email>` in a terminal.
"""
import json
import re
import shutil
import subprocess

TIMEOUT = 25


def run(*args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=TIMEOUT)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return -1, ""


def main():
    out = {"installed": False, "loggedIn": False, "state": "missing", "used": 0, "total": 0,
           "syncs": [], "uploads": 0, "downloads": 0, "percent": 0}
    if not shutil.which("mega-whoami"):
        return out
    out["installed"] = True
    out["state"] = "offline"

    code, text = run("mega-whoami")
    if code != 0 or "@" not in text:
        return out
    out["loggedIn"] = True

    code, text = run("mega-df")
    m = re.search(r"USED STORAGE:\s*(\d+)\s+[\d.]+%\s+of\s+(\d+)", text)
    if m:
        out["used"], out["total"] = int(m.group(1)), int(m.group(2))

    code, text = run("mega-sync", "--col-separator=\t",
                     "--output-cols=LOCALPATH,REMOTEPATH,RUN_STATE,STATUS,ERROR")
    for line in text.splitlines()[1:]:
        cols = [c.strip() for c in line.split("\t")]
        if len(cols) >= 4 and cols[0]:
            err = cols[4] if len(cols) > 4 and cols[4] not in ("", "NO", "-") else ""
            out["syncs"].append({"local": cols[0], "remote": cols[1], "run": cols[2],
                                 "status": cols[3], "error": err})

    code, text = run("mega-transfers", "--summary")
    nums = text.splitlines()[1].split() if len(text.splitlines()) > 1 else []
    # NUM_DL DL_DONE unit DL_TOTAL unit DL% NUM_UL UL_DONE unit UL_TOTAL unit UL%
    if len(nums) >= 12:
        try:
            out["downloads"], out["uploads"] = int(nums[0]), int(nums[6])
            pcts = [float(nums[i].rstrip("%")) for i in (5, 11)
                    if int(nums[0 if i == 5 else 6]) > 0]
            out["percent"] = round(min(pcts)) if pcts else 0
        except ValueError:
            pass

    if any(s["error"] or s["run"] in ("Suspended", "Disabled") for s in out["syncs"]):
        out["state"] = "error"
    elif out["uploads"] or out["downloads"] or any(
            s["status"] in ("Syncing", "Pending", "Processing") or s["run"] in ("Pending", "Loading")
            for s in out["syncs"]):
        out["state"] = "syncing"
    else:
        out["state"] = "synced"
    return out


if __name__ == "__main__":
    print(json.dumps(main()))
