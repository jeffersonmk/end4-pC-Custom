#!/usr/bin/env python3
"""Set the light bar colour of connected DualSense controllers (stdlib only).

    dualsense_light.py set R G B     colour, 0-255 each
    dualsense_light.py off           light bar off
    dualsense_light.py restore       the colour the kernel driver sets on connect (blue)
    dualsense_light.py list          print the hidraw nodes that would be used

Writes one output report straight to the controller's hidraw node (what SDL and
games do), so no root and no kernel LED permissions are needed; the hidraw node
must be writable by the user (steam-devices / game-devices-udev rules do that).
Only the light bar is touched: the report's valid flags leave rumble, player
LEDs and audio alone. Prints one JSON line: {"ok": bool, "devices": n, ...}.
Reconnecting the controller also brings back the driver's colour.
"""
import glob
import json
import os
import struct
import sys
import zlib

SONY = 0x054C
DUALSENSE = (0x0CE6, 0x0DF2)  # DualSense, DualSense Edge
BUS_USB, BUS_BT = 0x0003, 0x0005
DRIVER_DEFAULT = (0, 0, 128)  # hid-playstation: dualsense_set_lightbar(ds, 0, 0, 128)


def find_nodes():
    nodes = []
    for sys_dir in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(os.path.join(sys_dir, "device", "uevent")) as f:
                info = dict(line.strip().split("=", 1) for line in f if "=" in line)
            bus, vid, pid = (int(x, 16) for x in info["HID_ID"].split(":"))
        except (OSError, KeyError, ValueError):
            continue
        if vid == SONY and pid in DUALSENSE and bus in (BUS_USB, BUS_BT):
            nodes.append(("/dev/" + os.path.basename(sys_dir), bus))
    return nodes


def common_block(red, green, blue):
    # struct dualsense_output_report_common (47 bytes), see hid-playstation.c
    block = bytearray(47)
    block[1] = 0x04            # valid_flag1: light bar control enable
    block[44:47] = bytes((red, green, blue))
    return bytes(block)


def build_report(bus, red, green, blue, seq=0):
    common = common_block(red, green, blue)
    if bus == BUS_USB:
        return b"\x02" + common + bytes(15)                        # 63 bytes
    body = bytes((0x31, (seq & 0x0F) << 4, 0x10)) + common + bytes(24)  # 74 bytes
    crc = zlib.crc32(b"\xa2" + body) & 0xFFFFFFFF                  # seed byte 0xA2
    return body + struct.pack("<I", crc)                           # 78 bytes


def main(argv):
    if len(argv) >= 2 and argv[1] == "list":
        print(json.dumps({"ok": True, "nodes": find_nodes()}))
        return 0
    if len(argv) == 5 and argv[1] == "set":
        try:
            colour = [int(x) for x in argv[2:5]]
        except ValueError:
            colour = [-1]
        if not all(0 <= c <= 255 for c in colour):
            print(json.dumps({"ok": False, "error": "bad_colour"}))
            return 2
    elif len(argv) == 2 and argv[1] == "off":
        colour = [0, 0, 0]
    elif len(argv) == 2 and argv[1] == "restore":
        colour = list(DRIVER_DEFAULT)
    else:
        print(json.dumps({"ok": False, "error": "usage"}))
        return 2

    nodes = find_nodes()
    if not nodes:
        print(json.dumps({"ok": False, "error": "no_device", "devices": 0}))
        return 1
    done, denied = 0, 0
    for path, bus in nodes:
        try:
            fd = os.open(path, os.O_WRONLY)
        except PermissionError:
            denied += 1
            continue
        except OSError:
            continue
        try:
            os.write(fd, build_report(bus, *colour))
            done += 1
        except OSError:
            pass
        finally:
            os.close(fd)
    if done == 0:
        print(json.dumps({"ok": False, "error": "no_permission" if denied else "write_failed", "devices": 0}))
        return 1
    print(json.dumps({"ok": True, "devices": done, "colour": colour}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
