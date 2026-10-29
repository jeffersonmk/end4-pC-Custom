#!/usr/bin/env python3
"""papirus-folder-color.py - match the Papirus folder icon color to the wallpaper.

Papirus ships every folder icon in ~25 colors, but the default color is a set of
symlinks inside the (root-owned) system theme. Instead of touching it, this script
builds a tiny user theme "<Base>-Folder-<color>" under ~/.local/share/icons that
inherits the Papirus theme and only repoints the folder symlinks, then activates it
through system-appearance.sh (KDE + GTK). Dolphin and other file managers pick it up
as a normal icon theme change.

Usage:
  papirus-folder-color.py --apply [--color #rrggbb | --folder NAME] [--dry-run]
  papirus-folder-color.py --restore
  papirus-folder-color.py --status

The color comes from --color, else the wallpaper seed color in
$XDG_STATE_HOME/quickshell/user/generated/color.txt, else $primary in material_colors.scss.
Only runs when the active icon theme is Papirus, Papirus-Dark, Papirus-Light or one of
their generated "-Folder-<color>" variants; any other theme is left alone.

Exit codes: 0 ok, 2 no color / palette, 3 active theme is not Papirus, 4 base theme missing.
"""
import argparse
import filecmp
import json
import math
import os
import re
import shutil
import subprocess
import sys

VERSION = 2
PALETTE_NAMES = [
    "adwaita", "black", "blue", "bluegrey", "breeze", "brown", "carmine", "cyan",
    "darkcyan", "deeporange", "green", "grey", "indigo", "magenta", "nordic", "orange",
    "palebrown", "paleorange", "pink", "red", "teal", "violet", "white", "yellow", "yaru",
]
NEUTRALS = {"black", "grey", "white", "bluegrey"}
THEME_RE = re.compile(r"^(?P<base>Papirus(?:-Dark|-Light)?)(?:-Folder-(?P<color>[a-z]+))?$")
HEX_RE = re.compile(r"#?([0-9a-fA-F]{6})")
PALETTE_SET = set(PALETTE_NAMES)
COLOR_DIRS = ("places", "mimetypes")  # where folder icons live


def home():
    return os.path.expanduser("~")


def data_home():
    return os.environ.get("XDG_DATA_HOME") or os.path.join(home(), ".local/share")


def state_home():
    return os.environ.get("XDG_STATE_HOME") or os.path.join(home(), ".local/state")


def source_dirs():
    extra = os.environ.get("PFC_SOURCE_DIRS")
    if extra:
        return [d for d in extra.split(":") if d]
    return ["/usr/share/icons", os.path.join(data_home(), "icons"), os.path.join(home(), ".icons")]


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def current_theme():
    value = run(["kreadconfig6", "--file", "kdeglobals", "--group", "Icons", "--key", "Theme"])
    if not value:
        value = run(["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"]).strip("'")
    return value


def set_theme(name):
    script = os.environ.get("PFC_SYSTEM_APPEARANCE") or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "system-appearance.sh")
    subprocess.run(["bash", script, "--set-icons", name], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)


# ---- color math (OKLab / OKLCH) -------------------------------------------------

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_oklch(value):
    m = HEX_RE.fullmatch(value.strip())
    if not m:
        raise ValueError(f"bad color: {value}")
    h = m.group(1)
    r, g, b = (srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    mm = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, mm, s = (math.copysign(abs(x) ** (1 / 3), x) for x in (l, mm, s))
    L = 0.2104542553 * l + 0.7936177850 * mm - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * mm + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * mm - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def hue_diff(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


# ---- palette ---------------------------------------------------------------------

def folder_front_color(svg_path):
    """Main (front) fill of a Papirus folder icon."""
    try:
        text = open(svg_path, encoding="utf-8").read()
    except OSError:
        return None
    best = None
    for m in re.finditer(r'<rect[^>]*style="fill:(#[0-9a-fA-F]{6})"[^>]*>', text):
        tag = m.group(0)
        if 'width="56"' in tag and 'height="36"' in tag:
            y = re.search(r'\by="([0-9.]+)"', tag)
            y = float(y.group(1)) if y else 0
            if best is None or y >= best[0]:
                best = (y, m.group(1))
    return best[1] if best else None


def read_palette(base_dir):
    palette = {}
    for name in PALETTE_NAMES:
        color = folder_front_color(os.path.join(base_dir, "64x64", "places", f"folder-{name}.svg"))
        if color:
            palette[name] = color
    return palette


def default_color(base_dir):
    link = os.path.realpath(os.path.join(base_dir, "64x64", "places", "folder.svg"))
    m = re.fullmatch(r"folder-([a-z]+)\.svg", os.path.basename(link))
    return m.group(1) if m else None


def nearest_color(target_hex, palette):
    """Closest Papirus color: by hue for colorful targets, by lightness for gray ones."""
    L, C, H = hex_to_oklch(target_hex)
    pal = {n: hex_to_oklch(h) for n, h in palette.items()}
    if C < 0.02:
        pool = {n: v for n, v in pal.items() if n in NEUTRALS}
        return min(pool, key=lambda n: abs(pool[n][0] - L)), pal
    pool = {n: v for n, v in pal.items() if n not in NEUTRALS and v[1] > 0.02}

    def cost(name):
        pl, pc, ph = pool[name]
        # hue dominates; chroma and lightness only break ties between similar hues
        return (hue_diff(H, ph) / 20.0) ** 2 + ((C - pc) / 0.08) ** 2 + ((L - pl) / 0.5) ** 2

    return min(pool, key=cost), pal


def wallpaper_color():
    gen = os.environ.get("PFC_STATE_DIR") or os.path.join(state_home(), "quickshell/user/generated")
    for fname, pattern in (("color.txt", r"#[0-9a-fA-F]{6}"),
                           ("material_colors.scss", r"\$primary:\s*(#[0-9a-fA-F]{6})")):
        try:
            text = open(os.path.join(gen, fname), encoding="utf-8").read()
        except OSError:
            continue
        m = re.search(pattern, text)
        if m:
            return m.group(m.lastindex or 0)
    return None


# ---- theme generation --------------------------------------------------------------

def parse_sections(index_path):
    sections, name, lines = {}, None, []
    for raw in open(index_path, encoding="utf-8", errors="replace").read().splitlines():
        m = re.fullmatch(r"\[(.+)\]", raw.strip())
        if m:
            if name is not None:
                sections[name] = lines
            name, lines = m.group(1), []
        elif name is not None and raw.strip():
            lines.append(raw.strip())
    if name is not None:
        sections[name] = lines
    return sections


def generated_dir(base, color):
    return os.path.join(data_home(), "icons", f"{base}-Folder-{color}")


def manifest_ok(path, base_dir, base, color):
    try:
        data = json.load(open(os.path.join(path, ".folder-color.json")))
        stamp = os.stat(os.path.join(base_dir, "index.theme")).st_mtime_ns
    except (OSError, ValueError):
        return False
    return (data.get("generated") is True and data.get("version") == VERSION and data.get("base") == base
            and data.get("color") == color and data.get("baseDir") == base_dir and data.get("baseStamp") == stamp)


def recolored(final, old, new):
    """Path of the `new` colored twin of icon file `final` (already symlink-resolved), or None.

    Matches icons that are in the theme's default color: explicit names like
    folder-<old>-docs.svg, and default names (folder.svg, user-home.svg ...) that are
    byte-identical to their folder-<old> twin (true for the small sizes, which are copies)."""
    folder, fname = os.path.dirname(final), os.path.basename(final)
    m = re.fullmatch(r"(folder|user)-%s(.*)\.svg" % re.escape(old), fname)
    if m:
        twin = os.path.join(folder, f"{m.group(1)}-{new}{m.group(2)}.svg")
        return twin if os.path.isfile(twin) else None
    m = re.fullmatch(r"(folder|user)(-.+)?\.svg", fname)
    if not m:
        return None
    rest = m.group(2) or ""
    if PALETTE_SET.intersection(rest.split("-")):
        return None
    base_twin = os.path.join(folder, f"{m.group(1)}-{old}{rest}.svg")
    twin = os.path.join(folder, f"{m.group(1)}-{new}{rest}.svg")
    if os.path.isfile(base_twin) and os.path.isfile(twin) and filecmp.cmp(final, base_twin, shallow=False):
        return twin
    return None


def generate(base, base_dir, old_color, new_color):
    """Build (or reuse) ~/.local/share/icons/<base>-Folder-<new_color>. Returns the theme name."""
    out = generated_dir(base, new_color)
    name = os.path.basename(out)
    if manifest_ok(out, base_dir, base, new_color):
        return name, 0
    sections = parse_sections(os.path.join(base_dir, "index.theme"))
    dir_line = next((l.split("=", 1)[1] for l in sections.get("Icon Theme", []) if l.startswith("Directories=")), "")
    dirs = [d.strip() for d in dir_line.split(",") if d.strip()]
    tmp = out + f".tmp-{os.getpid()}"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    written, kept, linked = 0, [], []
    for d in dirs:
        if d.split("/")[-1] not in COLOR_DIRS:
            continue
        src = os.path.join(base_dir, d)
        top = os.path.join(base_dir, d.split("/")[0])
        if os.path.islink(top) and "/" not in os.readlink(top):
            # alias such as "16x16@2x" -> "16x16": recreate the alias below
            linked.append(d)
            continue
        if not os.path.isdir(src):
            continue
        made = 0
        real = os.path.realpath(src)
        for entry in os.scandir(src):
            if not entry.name.endswith(".svg"):
                continue
            target = recolored(os.path.realpath(entry.path), old_color, new_color)
            if not target:
                continue
            os.makedirs(os.path.join(tmp, d), exist_ok=True)
            os.symlink(target, os.path.join(tmp, d, entry.name))
            made += 1
        if made:
            kept.append(d)
            written += made
    for d in linked:
        parent, leaf = d.split("/", 1)
        alias_src = os.path.join(base_dir, parent)
        if os.path.islink(alias_src):
            real_parent = os.readlink(alias_src)
            if os.path.isdir(os.path.join(tmp, real_parent, leaf)):
                alias = os.path.join(tmp, parent)
                if not os.path.lexists(alias):
                    os.symlink(real_parent, alias)
                kept.append(d)
    if not written:
        shutil.rmtree(tmp, ignore_errors=True)
        raise RuntimeError(f"no folder icons found for color {new_color}")
    lines = ["[Icon Theme]", f"Name={name}",
             f"Comment=Generated by the shell: {base} with {new_color} folders. Safe to delete.",
             f"Inherits={base}", "Hidden=true", f"Directories={','.join(sorted(set(kept)))}", ""]
    for d in sorted(set(kept)):
        lines.append(f"[{d}]")
        lines.extend(sections.get(d, ["Size=48", "Type=Fixed", "Context=Places"]))
        lines.append("")
    with open(os.path.join(tmp, "index.theme"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    with open(os.path.join(tmp, ".folder-color.json"), "w") as fh:
        json.dump({"generated": True, "version": VERSION, "base": base, "color": new_color,
                   "baseDir": base_dir,
                   "baseStamp": os.stat(os.path.join(base_dir, "index.theme")).st_mtime_ns}, fh)
    if os.path.isdir(out):
        # only ever replace a directory this script generated
        if not os.path.isfile(os.path.join(out, ".folder-color.json")):
            shutil.rmtree(tmp, ignore_errors=True)
            raise RuntimeError(f"{out} exists and was not generated by this script")
        shutil.rmtree(out)
    os.replace(tmp, out)
    return name, written


# ---- commands ----------------------------------------------------------------------

def find_base_dir(base):
    for d in source_dirs():
        p = os.path.join(d, base)
        if os.path.isfile(os.path.join(p, "index.theme")) and not os.path.isfile(os.path.join(p, ".folder-color.json")):
            return p
    return None


def cmd_apply(args):
    cur = current_theme()
    m = THEME_RE.match(cur or "")
    if not m:
        print(json.dumps({"ok": False, "reason": "active icon theme is not Papirus", "theme": cur}))
        return 3
    base = m.group("base")
    base_dir = find_base_dir(base)
    if not base_dir:
        print(json.dumps({"ok": False, "reason": f"{base} not found"}))
        return 4
    palette = read_palette(base_dir)
    color_hex = args.color or wallpaper_color()
    if not palette or not (color_hex or args.folder):
        print(json.dumps({"ok": False, "reason": "no palette or no wallpaper color"}))
        return 2
    default = default_color(base_dir)
    if args.folder:
        if args.folder not in palette:
            print(json.dumps({"ok": False, "reason": f"unknown Papirus color: {args.folder}", "colors": sorted(palette)}))
            return 2
        chosen, color_hex = args.folder, palette[args.folder]
    else:
        chosen, _ = nearest_color(color_hex, palette)
    result = {"ok": True, "source": color_hex, "color": chosen, "swatch": palette[chosen], "base": base,
              "systemDefault": default, "previous": cur}
    if args.dry_run:
        result["theme"] = base if chosen == default else f"{base}-Folder-{chosen}"
        print(json.dumps(result))
        return 0
    if chosen == default or default is None:
        target = base  # the system theme already has this color
    else:
        target, written = generate(base, base_dir, default, chosen)
        result["files"] = written
    result["theme"] = target
    if target != cur:
        set_theme(target)
    print(json.dumps(result))
    return 0


def cmd_restore(args):
    cur = current_theme()
    m = THEME_RE.match(cur or "")
    if not m or not m.group("color"):
        print(json.dumps({"ok": True, "changed": False, "theme": cur}))
        return 0
    set_theme(m.group("base"))
    print(json.dumps({"ok": True, "changed": True, "theme": m.group("base")}))
    return 0


def cmd_status(args):
    cur = current_theme()
    m = THEME_RE.match(cur or "")
    print(json.dumps({"theme": cur, "papirus": bool(m), "folderColor": m.group("color") if m else None,
                      "wallpaperColor": wallpaper_color()}))
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--apply", action="store_true")
    g.add_argument("--restore", action="store_true")
    g.add_argument("--status", action="store_true")
    ap.add_argument("--color", help="source color (#rrggbb); default: wallpaper color")
    ap.add_argument("--folder", help="use this Papirus color name (e.g. teal) instead of matching a source color")
    ap.add_argument("--dry-run", action="store_true", help="only print the choice")
    args = ap.parse_args()
    sys.dont_write_bytecode = True
    try:
        if args.apply:
            return cmd_apply(args)
        if args.restore:
            return cmd_restore(args)
        return cmd_status(args)
    except (OSError, RuntimeError, ValueError) as e:
        print(json.dumps({"ok": False, "reason": str(e)}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
