#!/usr/bin/env python3
"""User-side: builds the SDDM 'corners' config from the shell's Material colors
and calls the root helper through sudo. Usage:
  sddm_apply.py [--image PATH] [--no-colors] [--user-picture] [--show-password]
                [--clock24] [--login-text TXT] [--radius N] [--dry-run]
"""
import argparse, json, os, subprocess, sys

HELPER = "/usr/local/bin/sddm-corners-apply"
COLORS = os.path.expanduser("~/.local/state/quickshell/user/generated/colors.json")

def palette(c):
    g = lambda k, fb: c.get(k, c.get(fb, "#808080"))
    return {
        "UserBorderColor": g("primary", "primary"), "UserColor": g("on_surface", "on_surface"),
        "InputColor": g("surface_container", "background"),
        "InputTextColor": g("on_surface", "on_surface"),
        "InputBorderColor": g("primary", "primary"),
        "LoginButtonColor": g("primary", "primary"),
        "LoginButtonTextColor": g("on_primary", "on_primary"),
        "PopupColor": g("surface_container_high", "surface_variant"),
        "PopupActiveColor": g("primary_container", "primary"),
        "PopupActiveTextColor": g("on_primary_container", "on_primary"),
        "SessionButtonColor": g("secondary_container", "secondary"),
        "SessionIconColor": g("on_secondary_container", "on_secondary"),
        "PowerButtonColor": g("secondary_container", "secondary"),
        "PowerIconColor": g("on_secondary_container", "on_secondary"),
        "DateColor": g("on_surface_variant", "on_surface"),
        "TimeColor": g("on_surface", "on_surface"),
    }

def main():
    a = argparse.ArgumentParser()
    a.add_argument("--image"); a.add_argument("--no-colors", action="store_true")
    a.add_argument("--user-picture", action="store_true")
    a.add_argument("--show-password", action="store_true")
    a.add_argument("--clock24", action="store_true")
    a.add_argument("--login-text"); a.add_argument("--radius")
    a.add_argument("--dry-run", action="store_true")
    o = a.parse_args()
    values = {}
    if not o.no_colors:
        with open(COLORS) as f:
            values.update(palette(json.load(f)))
    values["UserPictureEnabled"] = "true" if o.user_picture else "false"
    values["HidePassword"] = "false" if o.show_password else "true"
    values["TimeFormat"] = "hh:mm" if o.clock24 else "hh:mm AP"
    if o.login_text: values["LoginButtonText"] = o.login_text
    if o.radius: values["Radius"] = o.radius
    payload = json.dumps({"image": os.path.realpath(o.image) if o.image else None, "values": values})
    if o.dry_run:
        print(payload); return
    r = subprocess.run(["sudo", "-n", HELPER], input=payload, text=True, capture_output=True)
    sys.stdout.write(r.stdout); sys.stderr.write(r.stderr)
    sys.exit(r.returncode)

main()
