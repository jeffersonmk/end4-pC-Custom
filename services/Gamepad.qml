pragma Singleton
pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Gamepad shortcut: pressing a chosen controller button runs a shell action
 * (by default it toggles the widget overlay, the same as Super + G).
 *
 * A small Python helper (scripts/gamepad/gamepad_listener.py) watches every
 * connected controller with evdev, read-only and without grabbing it, so games
 * still get all buttons. It's only started when the feature is enabled.
 *
 * While the widget overlay is open the listener also reports the d-pad / left
 * stick and the other buttons (navigation mode), which OverlayGamepadNavigator
 * uses to move around the overlay. Outside the overlay only the toggle button
 * is watched.
 *
 * Config: Config.options.gamepad.{enable, button, action, navigateOverlay}
 */
Singleton {
    id: root

    readonly property bool enabled: Config.ready && (Config.options.gamepad?.enable ?? false)
    readonly property string button: Config.options.gamepad?.button || "BTN_MODE"
    readonly property string action: Config.options.gamepad?.action || "overlayOpen"

    property var devices: []          // [{name, brand}] of the connected controllers
    property string error: ""         // "", "no_evdev", "no_permission", "crashed"
    property bool learning: false      // waiting for a button press to pick it
    property string lastPressed: ""   // last time the button fired (for the settings page)

    readonly property bool connected: devices.length > 0
    // "xbox" | "playstation" | "nintendo" | "generic" | "" (none connected)
    // The controller that last pressed the shortcut button wins (several can be connected)
    property string activeBrand: ""
    readonly property string brand: root.activeBrand !== "" && root.devices.some(d => d.brand === root.activeBrand)
        ? root.activeBrand : (devices.length > 0 ? (devices[0].brand ?? "generic") : "")
    readonly property string deviceName: devices.length > 0 ? devices[0].name : ""

    // Overlay navigation is on while the overlay is open and a controller is connected
    readonly property bool navActive: root.enabled && root.connected && !root.learning
        && (Config.options.gamepad?.navigateOverlay ?? true) && GlobalStates.overlayOpen
    onNavActiveChanged: root.sendNavMode()

    // Pause the game behind the overlay while it's open. Needed for controllers that games
    // read directly (hidraw), which the controller grab can't block: PlayStation and
    // Nintendo pads in emulators/Steam. Xbox pads are blocked by the grab already.
    // Separate options for Xbox/standard pads and for PlayStation/Nintendo pads; the
    // controller in use (the one that opened the overlay) decides.
    readonly property bool brandReadDirectly: root.brand === "playstation" || root.brand === "nintendo"
    readonly property bool pauseWanted: root.navActive && (root.brandReadDirectly
        ? (Config.options.gamepad?.pauseGameDirect ?? true)
        : (Config.options.gamepad?.pauseGameXbox ?? false))
    onPauseWantedChanged: root.sendPauseMode()
    property string pausedGame: ""
    function sendPauseMode() {
        if (listenProc.running) listenProc.write(root.pauseWanted ? "pause\n" : "resume\n");
    }

    signal navigated(string direction)   // "up" | "down" | "left" | "right"
    signal buttonPressed(string button)  // evdev name, e.g. "BTN_SOUTH"

    // Nerd Font glyphs (Material Design Icons set) for each brand
    readonly property var brandGlyphs: ({
        "xbox": String.fromCodePoint(0xF05B9),
        "playstation": String.fromCodePoint(0xF0414),
        "nintendo": String.fromCodePoint(0xF07E1),
        "generic": String.fromCodePoint(0xF02B4),
    })
    readonly property string brandGlyph: root.brandGlyphs[root.brand] ?? root.brandGlyphs.generic
    readonly property var brandNames: ({
        "xbox": "Xbox",
        "playstation": "PlayStation",
        "nintendo": "Nintendo",
        "generic": Translation.tr("Controller"),
    })

    // What is printed on each button, per brand (by position: south = bottom face button)
    readonly property var buttonLabels: ({
        "xbox": { "BTN_SOUTH": "A", "BTN_EAST": "B", "BTN_NORTH": "Y", "BTN_WEST": "X", "BTN_TL": "LB", "BTN_TR": "RB", "BTN_START": "☰", "BTN_SELECT": "⧉", "BTN_MODE": "Xbox" },
        "playstation": { "BTN_SOUTH": "✕", "BTN_EAST": "○", "BTN_NORTH": "△", "BTN_WEST": "□", "BTN_TL": "L1", "BTN_TR": "R1", "BTN_START": "Options", "BTN_SELECT": "Share", "BTN_MODE": "PS" },
        "nintendo": { "BTN_SOUTH": "B", "BTN_EAST": "A", "BTN_NORTH": "X", "BTN_WEST": "Y", "BTN_TL": "L", "BTN_TR": "R", "BTN_START": "+", "BTN_SELECT": "−", "BTN_MODE": "Home" },
    })
    function buttonGlyph(button) {
        const set = root.buttonLabels[root.brand] ?? root.buttonLabels.xbox;
        return set[button] ?? button.replace("BTN_", "");
    }

    function sendNavMode() {
        if (listenProc.running) listenProc.write(root.navActive ? "nav on\n" : "nav off\n");
    }

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/gamepad/gamepad_listener.py`)

    // Friendly names for the usual buttons (evdev names → what's printed on the pad)
    readonly property var buttonNames: ({
        "BTN_MODE": Translation.tr("Home / Guide (Xbox, PS, Nintendo logo)"),
        "BTN_SOUTH": Translation.tr("A / Cross (bottom)"),
        "BTN_EAST": Translation.tr("B / Circle (right)"),
        "BTN_NORTH": Translation.tr("Y / Triangle (top)"),
        "BTN_WEST": Translation.tr("X / Square (left)"),
        "BTN_START": Translation.tr("Start / Menu / Options"),
        "BTN_SELECT": Translation.tr("Select / View / Share"),
        "BTN_TL": Translation.tr("Left bumper (LB / L1)"),
        "BTN_TR": Translation.tr("Right bumper (RB / R1)"),
        "BTN_TL2": Translation.tr("Left trigger (LT / L2)"),
        "BTN_TR2": Translation.tr("Right trigger (RT / R2)"),
        "BTN_THUMBL": Translation.tr("Left stick click (L3)"),
        "BTN_THUMBR": Translation.tr("Right stick click (R3)"),
    })
    function buttonLabel(name) {
        return root.buttonNames[name] ?? name;
    }

    function load() {
        // dummy to force init
    }

    function trigger() {
        root.lastPressed = Qt.formatDateTime(new Date(), Config.options.time.format + ":ss");
        GlobalStates.toggleState(root.action);
    }

    function startLearning() {
        root.learning = true;
        learnProc.running = true;
    }
    function cancelLearning() {
        root.learning = false;
        learnProc.running = false;
    }

    function handleLine(line, learn) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;
        }
        switch (msg.event) {
        case "devices":
            root.devices = msg.devices ?? [];
            root.error = "";
            break;
        case "error":
            root.error = msg.error ?? "crashed";
            break;
        case "press":
            if (!learn) {
                const pressed = root.devices.find(d => d.name === msg.device);
                if (pressed) root.activeBrand = pressed.brand ?? "generic";
                root.trigger();
            }
            break;
        case "nav":
            if (!learn && root.navActive) root.navigated(msg.dir);
            break;
        case "button":
            if (!learn && root.navActive) root.buttonPressed(msg.button);
            break;
        case "paused":
            root.pausedGame = msg.name ?? "";
            break;
        case "resumed":
            root.pausedGame = "";
            break;
        case "learned":
            if (learn) {
                Config.options.gamepad.button = msg.button;
                root.learning = false;
            }
            break;
        }
    }

    // Main listener: runs only while enabled (and not while learning a new button)
    Process {
        id: listenProc
        running: root.enabled && !root.learning
        command: ["python3", root.scriptPath, "listen", root.button]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => root.handleLine(line, false)
        }
        onRunningChanged: {
            if (running) {
                root.sendNavMode();
                if (root.pauseWanted) root.sendPauseMode();
            } else {
                root.pausedGame = "";
                if (!root.enabled) root.devices = [];
            }
        }
        onExited: (code, status) => {
            // Restart after an unexpected exit (e.g. Python error), with a small delay
            if (root.enabled && !root.learning && code !== 0) {
                root.error = "crashed";
                restartTimer.restart();
            }
        }
    }
    Timer {
        id: restartTimer
        interval: 5000
        onTriggered: if (root.enabled && !root.learning) listenProc.running = true
    }

    // "Press a button" picker
    Process {
        id: learnProc
        command: ["python3", root.scriptPath, "learn"]
        stdout: SplitParser {
            onRead: line => root.handleLine(line, true)
        }
        onExited: root.learning = false
    }
    Timer {
        // Give up the picker after 15 s without a press
        running: root.learning
        interval: 15000
        onTriggered: root.cancelLearning()
    }
}
