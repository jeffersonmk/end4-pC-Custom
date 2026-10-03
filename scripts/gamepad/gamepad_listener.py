#!/usr/bin/env python3
"""
Gamepad listener for the shell.

Watches every connected game controller (USB or Bluetooth, hot-plug included)
and prints one JSON object per line on stdout:

  {"event": "devices", "devices": [{"name": "...", "brand": "playstation"}, ...]}
                                                  whenever the list changes
  {"event": "press", "button": "BTN_MODE", "device": "..."}
                                                  listen mode: the toggle button was pressed
  {"event": "nav", "dir": "up|down|left|right"}  navigation mode only (d-pad / left stick,
                                                  with auto-repeat while held)
  {"event": "button", "button": "BTN_SOUTH", "brand": "..."}
                                                  navigation mode only: any other button press
  {"event": "learned", "button": "BTN_MODE", "device": "..."}
                                                  learn mode: first button pressed (then exits)
  {"event": "error", "error": "no_evdev" | "no_permission"}

Navigation mode is switched by writing "nav on" / "nav off" lines to stdin, so
directions and buttons are only reported while the shell needs them (e.g. while
the widget overlay is open), not during games.

Usage:
  gamepad_listener.py listen [BUTTON_NAME]   (default BTN_MODE = Xbox/PS/"home" button)
  gamepad_listener.py learn                  (reports the next button pressed, then exits)

Notes:
- Devices are opened read-only. Outside navigation mode they are never grabbed,
  so games keep receiving every button as usual; during navigation mode they
  are grabbed so the game behind the overlay doesn't react too.
- Needs read access to /dev/input/event* (the "input" group, or the udev
  uaccess rule most distros ship for game controllers).
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
REPEAT_DELAY = 0.40       # hold a direction this long before it starts repeating
REPEAT_INTERVAL = 0.12
STICK_ON = 0.60           # stick deflection (0..1) that counts as a direction
STICK_OFF = 0.40          # ...and that releases it again (hysteresis)
GAMEPAD_HINTS = {ecodes.BTN_GAMEPAD, ecodes.BTN_SOUTH, ecodes.BTN_JOYSTICK, ecodes.BTN_MODE}

VENDOR_BRANDS = {0x045E: "xbox", 0x054C: "playstation", 0x057E: "nintendo"}
NAME_BRANDS = (
    ("xbox", "xbox"), ("x-box", "xbox"), ("microsoft", "xbox"),
    ("dualsense", "playstation"), ("dualshock", "playstation"), ("playstation", "playstation"),
    ("sony", "playstation"), ("ps3", "playstation"), ("ps4", "playstation"), ("ps5", "playstation"),
    ("nintendo", "nintendo"), ("pro controller", "nintendo"), ("joy-con", "nintendo"), ("switch", "nintendo"),
)
DPAD_BUTTONS = {
    ecodes.BTN_DPAD_UP: "up", ecodes.BTN_DPAD_DOWN: "down",
    ecodes.BTN_DPAD_LEFT: "left", ecodes.BTN_DPAD_RIGHT: "right",
}


def emit(obj):
    print(json.dumps(obj), flush=True)


def button_name(code):
    name = ecodes.BTN.get(code) or ecodes.KEY.get(code) or str(code)
    if isinstance(name, (list, tuple)):
        # Prefer the generic positional names (BTN_SOUTH over BTN_A/BTN_GAMEPAD)
        for preferred in name:
            if preferred.startswith(("BTN_SOUTH", "BTN_EAST", "BTN_NORTH", "BTN_WEST")):
                return preferred
        return name[0]
    return name


def brand_of(dev):
    vendor = getattr(dev.info, "vendor", 0)
    if vendor in VENDOR_BRANDS:
        return VENDOR_BRANDS[vendor]
    lowered = dev.name.lower()
    for needle, brand in NAME_BRANDS:
        if needle in lowered:
            return brand
    return "generic"


def is_gamepad(dev):
    try:
        keys = set(dev.capabilities().get(ecodes.EV_KEY, []))
    except OSError:
        return False
    # Keyboards also expose lots of keys; require a gamepad/joystick button
    return bool(keys & GAMEPAD_HINTS) and ecodes.KEY_A not in keys


def is_steam_virtual(dev):
    # Steam Input re-emits the physical controller as a virtual one; reading both
    # would double every press, so the virtual copy is ignored when a real one exists
    return getattr(dev.info, "vendor", 0) == 0x28DE and getattr(dev.info, "product", 0) == 0x11FF


def without_duplicates(found):
    if any(not is_steam_virtual(d) for d in found.values()):
        return {p: d for p, d in found.items() if not is_steam_virtual(d)}
    return found


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
    if not found and os.path.exists("/dev/input/event0") and not os.access("/dev/input/event0", os.R_OK):
        permission_problem = True
    return found, permission_problem


def hid_parent(path):
    """sysfs node of the physical device an event node belongs to (a DualSense shows up
    as several nodes: buttons, touchpad, motion sensors... all under the same parent)."""
    try:
        return os.path.realpath(f"/sys/class/input/{os.path.basename(path)}/device/device")
    except OSError:
        return None


def open_companions(devices):
    """Opens the other event nodes of the connected controllers (touchpad, motion
    sensors), so they can be grabbed too: otherwise the DualSense touchpad keeps
    moving the mouse and clicking in the app behind the overlay."""
    # uinput devices (Steam's virtual pad, ydotool...) all share one virtual parent;
    # never pull those in
    parents = {hid_parent(p) for p in devices} - {None}
    parents = {x for x in parents if "/virtual/" not in x}
    companions = {}
    for path in evdev.list_devices():
        if path in devices or hid_parent(path) not in parents:
            continue
        try:
            companions[path] = evdev.InputDevice(path)
        except OSError:
            pass
    return companions


# ---- pausing the game behind the overlay
# Some games read controllers through hidraw (e.g. PCSX2's DualSense/DualShock
# "enhanced mode", Steam Input), which an evdev grab can't block. For those the game
# is paused instead (SIGSTOP) while the overlay is open, and resumed (SIGCONT) when
# it closes. The PIDs are written to a state file so a crash/restart of the shell
# never leaves a game frozen.
STATE_FILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "quickshell-gamepad-paused.json")
EMULATOR_CLASSES = ("pcsx2", "rpcs3", "dolphin", "duckstation", "ppsspp", "cemu", "yuzu", "suyu",
                    "citron", "ryujinx", "eden", "retroarch", "xemu", "xenia", "shadps4", "azahar",
                    "lime3ds", "citra", "melonds", "flycast", "mgba", "redream", "vita3k")
NEVER_PAUSE = {"Hyprland", "qs", "quickshell", "systemd", "kitty", "steam", "steamwebhelper"}


def hypr(*args):
    import subprocess
    try:
        return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def looks_like_game(win):
    cls = (win.get("class") or win.get("initialClass") or "").lower()
    if cls.startswith("steam_app_") or "gamescope" in cls:
        return True
    if any(e in cls for e in EMULATOR_CLASSES):
        return True
    # Anything else fullscreen (games launched outside Steam, Wine/Lutris/Heroic...)
    return bool(win.get("fullscreen"))


def process_tree(root_pid):
    """root_pid plus all its descendants (games often run in child processes: Proton,
    wine, launchers...)."""
    children = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat") as f:
                stat = f.read()
            ppid = int(stat[stat.rindex(")") + 2:].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        children.setdefault(ppid, []).append(int(entry))
    pids, todo = [], [root_pid]
    while todo:
        pid = todo.pop()
        if pid in pids:
            continue
        pids.append(pid)
        todo.extend(children.get(pid, []))
    return pids


def comm_of(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except OSError:
        return ""


def send_signal(pids, sig):
    for pid in pids:
        try:
            os.kill(pid, sig)
        except OSError:
            pass


def anr_dialog_enabled():
    try:
        return bool(json.loads(hypr("getoption", "misc:enable_anr_dialog", "-j")).get("bool", True))
    except ValueError:
        return True


def set_anr_dialog(on):
    # A stopped game stops answering pings; don't let Hyprland pop "not responding"
    hypr("eval", f"hl.config({{ misc = {{ enable_anr_dialog = {'true' if on else 'false'} }} }})")


def pause_game():
    """Pauses the focused window's process tree if it looks like a game.
    Returns the paused state dict, or None."""
    import signal
    try:
        win = json.loads(hypr("activewindow", "-j") or "{}")
    except ValueError:
        return None
    pid = int(win.get("pid") or 0)
    if pid <= 1 or pid == os.getpid() or not looks_like_game(win):
        return None
    pids = [p for p in process_tree(pid) if comm_of(p) not in NEVER_PAUSE and p != os.getpid()]
    if not pids:
        return None
    state = {"pids": pids, "anr": anr_dialog_enabled(), "name": win.get("title") or win.get("class") or ""}
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except OSError:
        pass
    if state["anr"]:
        set_anr_dialog(False)
    send_signal(pids, signal.SIGSTOP)
    return state


def resume_game(state):
    import signal
    if not state:
        return
    send_signal(state.get("pids", []), signal.SIGCONT)
    if state.get("anr", True):
        set_anr_dialog(True)
    try:
        os.remove(STATE_FILE)
    except OSError:
        pass


def resume_leftover():
    """A previous listener died while a game was paused: resume it."""
    try:
        with open(STATE_FILE) as f:
            state = json.load(f)
    except (OSError, ValueError):
        return
    resume_game(state)


def close_all(devs):
    for dev in devs.values():
        try:
            dev.close()
        except OSError:
            pass


def set_grab(devices, grab):
    """While navigating the shell, take the controllers for ourselves so the game
    or app behind the overlay doesn't also react to the buttons. Released when
    navigation ends, and automatically by the kernel if this process exits."""
    for dev in devices.values():
        try:
            if grab:
                dev.grab()
            else:
                dev.ungrab()
        except OSError:
            pass


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


class Navigator:
    """Turns d-pad / hat / left stick input into discrete, auto-repeating directions."""

    def __init__(self):
        self.held = None          # (direction, source)
        self.next_repeat = 0.0
        self.stick = {}           # (path, axis) -> current direction or None

    def press(self, direction, source):
        self.held = (direction, source)
        self.next_repeat = time.monotonic() + REPEAT_DELAY
        emit({"event": "nav", "dir": direction})

    def release(self, source):
        if self.held and self.held[1] == source:
            self.held = None

    def reset(self):
        self.held = None
        self.stick.clear()

    def timeout(self):
        if not self.held:
            return None
        return max(0.0, self.next_repeat - time.monotonic())

    def tick(self):
        if self.held and time.monotonic() >= self.next_repeat:
            self.next_repeat = time.monotonic() + REPEAT_INTERVAL
            emit({"event": "nav", "dir": self.held[0]})

    def hat(self, path, axis, value):
        source = (path, "hat", axis)
        if value == 0:
            self.release(source)
        elif axis == ecodes.ABS_HAT0X:
            self.press("left" if value < 0 else "right", source)
        else:
            self.press("up" if value < 0 else "down", source)

    def stick_axis(self, dev, path, axis, value):
        try:
            info = dev.absinfo(axis)
        except OSError:
            return
        span = (info.max - info.min) / 2 or 1
        norm = (value - (info.max + info.min) / 2) / span
        key = (path, axis)
        current = self.stick.get(key)
        source = (path, "stick", axis)
        if current is None and abs(norm) >= STICK_ON:
            if axis == ecodes.ABS_X:
                direction = "left" if norm < 0 else "right"
            else:
                direction = "up" if norm < 0 else "down"
            self.stick[key] = direction
            self.press(direction, source)
        elif current is not None and abs(norm) < STICK_OFF:
            self.stick[key] = None
            self.release(source)


def main():
    die_with_parent()
    parent = os.getppid()
    mode = sys.argv[1] if len(sys.argv) > 1 else "listen"
    wanted = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else "BTN_MODE"
    wanted_code = ecodes.ecodes.get(wanted)

    devices = {}
    last_list = None
    last_scan = 0.0
    last_press = 0.0
    reported_permission = False
    nav_on = False
    companions = {}
    global paused
    if mode == "listen":
        resume_leftover()
    nav = Navigator()
    stdin_open = mode == "listen" and not sys.stdin.isatty()
    stdin_buffer = b""

    while True:
        if os.getppid() != parent:
            return
        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            previous = set(devices)
            devices, permission_problem = scan(devices)
            last_scan = now
            if nav_on and set(devices) != previous:
                set_grab({p: d for p, d in devices.items() if p not in previous}, True)
                set_grab(companions, False)
                close_all(companions)
                companions = open_companions(devices)
                set_grab(companions, True)
            active = without_duplicates(devices)
            listing = sorted(({"name": d.name, "brand": brand_of(d)} for d in active.values()),
                             key=lambda d: d["name"])
            if listing != last_list:
                emit({"event": "devices", "devices": listing})
                last_list = listing
            if permission_problem and not devices and not reported_permission:
                emit({"event": "error", "error": "no_permission"})
                reported_permission = True

        fds = {dev.fd: path for path, dev in without_duplicates(devices).items()}
        watch = list(fds)
        if stdin_open:
            watch.append(0)
        wait = RESCAN_SECONDS
        repeat_in = nav.timeout() if nav_on else None
        if repeat_in is not None:
            wait = min(wait, repeat_in)
        if not watch:
            time.sleep(wait)
            continue
        try:
            ready, _, _ = select.select(watch, [], [], wait)
        except (OSError, ValueError):
            last_scan = 0.0
            continue

        if nav_on:
            nav.tick()

        for fd in ready:
            if fd == 0:
                chunk = os.read(0, 1024)
                if not chunk:
                    stdin_open = False
                    continue
                stdin_buffer += chunk
                while b"\n" in stdin_buffer:
                    line, stdin_buffer = stdin_buffer.split(b"\n", 1)
                    command = line.decode(errors="ignore").strip()
                    if command == "nav on" and not nav_on:
                        nav_on = True
                        set_grab(devices, True)
                        companions = open_companions(devices)
                        set_grab(companions, True)
                    elif command == "nav off" and nav_on:
                        nav_on = False
                        nav.reset()
                        set_grab(devices, False)
                        set_grab(companions, False)
                        close_all(companions)
                        companions = {}
                    elif command == "pause" and paused is None:
                        paused = pause_game()
                        if paused:
                            emit({"event": "paused", "name": paused["name"]})
                    elif command == "resume" and paused is not None:
                        # Let the controller grab go first, so the game doesn't see the
                        # button that closed the overlay
                        time.sleep(0.25)
                        resume_game(paused)
                        paused = None
                        emit({"event": "resumed"})
                continue

            path = fds[fd]
            dev = devices.get(path)
            if dev is None:
                continue
            try:
                events = list(dev.read())
            except OSError:
                # Unplugged: force a rescan
                devices.pop(path, None)
                nav.reset()
                last_scan = 0.0
                continue
            for ev in events:
                if ev.type == ecodes.EV_KEY:
                    if mode == "learn":
                        if ev.value == 1:
                            emit({"event": "learned", "button": button_name(ev.code), "device": dev.name})
                            return
                        continue
                    if ev.code == wanted_code:
                        if ev.value == 1:
                            t = time.monotonic()
                            if t - last_press >= DEBOUNCE_SECONDS:
                                last_press = t
                                emit({"event": "press", "button": wanted, "device": dev.name})
                        continue
                    if not nav_on:
                        continue
                    if ev.code in DPAD_BUTTONS:
                        source = (path, "dpad", ev.code)
                        if ev.value == 1:
                            nav.press(DPAD_BUTTONS[ev.code], source)
                        elif ev.value == 0:
                            nav.release(source)
                    elif ev.value == 1:
                        emit({"event": "button", "button": button_name(ev.code), "brand": brand_of(dev)})
                elif ev.type == ecodes.EV_ABS and nav_on and mode == "listen":
                    if ev.code in (ecodes.ABS_HAT0X, ecodes.ABS_HAT0Y):
                        nav.hat(path, ev.code, ev.value)
                    elif ev.code in (ecodes.ABS_X, ecodes.ABS_Y):
                        nav.stick_axis(dev, path, ev.code, ev.value)


paused = None

if __name__ == "__main__":
    import signal
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    finally:
        # Never leave a game frozen (shell closed/restarted, listener stopped...)
        resume_game(paused)
