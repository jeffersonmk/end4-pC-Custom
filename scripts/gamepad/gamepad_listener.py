#!/usr/bin/env python3
"""
Gamepad button listener for the shell (opens the widget overlay, like Super + G).

Watches every connected game controller (USB or Bluetooth, hot-plug included)
and prints one JSON object per line on stdout:

  {"event": "devices", "devices": ["Xbox Wireless Controller", ...]}  whenever the list changes
  {"event": "press", "button": "BTN_MODE", "device": "..."}         listen mode: the chosen button was pressed
  {"event": "learned", "button": "BTN_MODE", "device": "..."}       learn mode: first button pressed (then exits)
  {"event": "error", "error": "no_evdev" | "no_permission"}

Usage:
  gamepad_listener.py listen [BUTTON_NAME]   (default BTN_MODE = Xbox/PS/"home" button)
  gamepad_listener.py learn                  (reports the next button pressed, then exits)

Notes:
- Devices are opened read-only and never grabbed, so games keep receiving
  every button as usual.
- Needs read access to /dev/input/event* (being in the "input" group, which is
  the default on Arch-based distros with systemd-logind seats... or a udev
  uaccess rule, which most distros ship for game controllers).
"""
import json
import os
import select
import sys
import time

try:
    import evdev
    from evdev import ecodes
except ImportError:
    print(json.dumps({"event": "error", "error": "no_evdev"}), flush=True)
    sys.exit(0)

RESCAN_SECONDS = 2.0
DEBOUNCE_SECONDS = 0.35
GAMEPAD_HINTS = {ecodes.BTN_GAMEPAD, ecodes.BTN_SOUTH, ecodes.BTN_JOYSTICK, ecodes.BTN_MODE}


def emit(obj):
    print(json.dumps(obj), flush=True)


def button_name(code):
    name = ecodes.BTN.get(code) or ecodes.KEY.get(code) or str(code)
    if isinstance(name, (list, tuple)):
        # Prefer the generic gamepad names (BTN_SOUTH over BTN_A/BTN_GAMEPAD)
        for preferred in name:
            if preferred.startswith(("BTN_SOUTH", "BTN_EAST", "BTN_NORTH", "BTN_WEST")):
                return preferred
        return name[0]
    return name


def is_gamepad(dev):
    try:
        keys = set(dev.capabilities().get(ecodes.EV_KEY, []))
    except OSError:
        return False
    # Keyboards also expose lots of keys; require a gamepad/joystick button
    return bool(keys & GAMEPAD_HINTS) and ecodes.KEY_A not in keys


def scan(known):
    """Returns (devices dict path->InputDevice, permission_problem)."""
    found = {}
    permission_problem = False
    for path in evdev.list_devices():
        if path in known:
            found[path] = known[path]
            continue
        try:
            dev = evdev.InputDevice(path)
        except PermissionError:
            permission_problem = True
            continue
        except OSError:
            continue
        if is_gamepad(dev):
            found[path] = dev
        else:
            dev.close()
    for path, dev in known.items():
        if path not in found:
            try:
                dev.close()
            except OSError:
                pass
    # No readable input device at all usually means missing permissions
    if not found and not os.access("/dev/input/event0", os.R_OK) and os.path.exists("/dev/input/event0"):
        permission_problem = True
    return found, permission_problem


def die_with_parent():
    """Exit when the shell that started us goes away (killall qs, crash, restart),
    so no orphan listener is left behind."""
    try:
        import ctypes
        import signal
        libc = ctypes.CDLL(None, use_errno=True)
        PR_SET_PDEATHSIG = 1
        libc.prctl(PR_SET_PDEATHSIG, signal.SIGTERM)
    except (OSError, AttributeError):
        pass
    # Covers the race where the parent died before prctl() ran
    if os.getppid() == 1:
        sys.exit(0)


def main():
    die_with_parent()
    parent = os.getppid()
    mode = sys.argv[1] if len(sys.argv) > 1 else "listen"
    wanted = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else "BTN_MODE"
    wanted_code = ecodes.ecodes.get(wanted)

    devices = {}
    last_names = None
    last_scan = 0.0
    last_press = 0.0
    reported_permission = False

    while True:
        if os.getppid() != parent:
            return
        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            devices, permission_problem = scan(devices)
            last_scan = now
            names = sorted(d.name for d in devices.values())
            if names != last_names:
                emit({"event": "devices", "devices": names})
                last_names = names
            if permission_problem and not devices and not reported_permission:
                emit({"event": "error", "error": "no_permission"})
                reported_permission = True

        if not devices:
            time.sleep(RESCAN_SECONDS)
            continue

        fds = {dev.fd: path for path, dev in devices.items()}
        try:
            ready, _, _ = select.select(list(fds), [], [], RESCAN_SECONDS)
        except (OSError, ValueError):
            last_scan = 0.0
            continue

        for fd in ready:
            path = fds[fd]
            dev = devices.get(path)
            if dev is None:
                continue
            try:
                events = list(dev.read())
            except OSError:
                # Unplugged: force a rescan
                devices.pop(path, None)
                last_scan = 0.0
                continue
            for ev in events:
                if ev.type != ecodes.EV_KEY or ev.value != 1:
                    continue
                if mode == "learn":
                    emit({"event": "learned", "button": button_name(ev.code), "device": dev.name})
                    return
                if ev.code == wanted_code:
                    t = time.monotonic()
                    if t - last_press >= DEBOUNCE_SECONDS:
                        last_press = t
                        emit({"event": "press", "button": wanted, "device": dev.name})


if __name__ == "__main__":
    import signal
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
