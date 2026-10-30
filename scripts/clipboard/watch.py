#!/usr/bin/env python3
"""Clipboard history watcher owned by the shell (Services.Cliphist).

  watch.py text|image [cliphist]   stop other cliphist watchers of that kind, then
                                   run `wl-paste --type <kind> --watch ...`
  watch.py kill                    stop every cliphist watcher (any owner) and exit

Each stored item makes the watch command print one line, which the shell reads to
refresh its list. Replaces the two `wl-paste ... --watch cliphist store` lines that
Hyprland's execs used to start, so the history can be switched off from Settings.
"""
import ctypes, os, signal, subprocess, sys


def watchers(kind=None):
    found = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        try:
            argv = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
        except OSError:
            continue
        if not argv or os.path.basename(argv[0]) != b"wl-paste":
            continue
        if b"--watch" not in argv or b"cliphist store" not in b" ".join(argv):
            continue
        if kind and (b"--type" not in argv or argv[argv.index(b"--type") + 1].decode() != kind):
            continue
        found.append(int(pid))
    return found


def stop(pids):
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "kill":
        stop(watchers())
        return
    if mode not in ("text", "image"):
        sys.exit("usage: watch.py text|image [cliphist] | kill")
    binary = sys.argv[2] if len(sys.argv) > 2 else "cliphist"
    libc = ctypes.CDLL(None)
    libc.prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG: never outlive the shell
    if os.getppid() == 1:
        return
    stop(watchers(mode))

    # `wl-paste --watch` also runs the command once for whatever is on the clipboard when it
    # starts. Skip that run: otherwise something copied while the history was switched off
    # would be stored the moment it is switched on again.
    mark = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), f"qs-cliphist-{mode}-{os.getpid()}")
    # The initial run only happens when the clipboard already offers this kind of content.
    listed = subprocess.run(["wl-paste", "-l"], capture_output=True, text=True).stdout.split()
    prefix = "text" if mode == "text" else "image/"
    if not any(t.startswith(prefix) for t in listed):
        open(mark, "w").close()  # nothing to skip: the first change is a real copy
    env = dict(os.environ, NF_MARK=mark)
    script = f'[ -e "$NF_MARK" ] || {{ : > "$NF_MARK"; exit 0; }}; {binary} store && echo 1'
    child = subprocess.Popen(["wl-paste", "--type", mode, "--watch", "bash", "-c", script], env=env,
                             preexec_fn=lambda: libc.prctl(1, signal.SIGTERM))

    def finish(*_):
        child.terminate()
        try:
            os.unlink(mark)
        except OSError:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, finish)
    child.wait()
    finish()


main()
