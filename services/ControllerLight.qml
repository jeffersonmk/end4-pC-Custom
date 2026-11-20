pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

// DualSense light bar: follow the theme (wallpaper colour), turn it off, or leave it alone.
// Mode lives in Config.options.gamepad.lightMode ("default" | "theme" | "off").
Singleton {
    id: root

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/gamepad/dualsense_light.py`)
    readonly property string mode: Config.options.gamepad.lightMode
    readonly property bool available: PeripheralBattery.controllers.some(dev => root.isDualSense(dev))

    // Light bar colour of the theme: the primary hue at a strong saturation,
    // pastel Material colours look washed out on an LED.
    readonly property color themeColor: {
        const c = Appearance.m3colors.m3primary
        const hue = c.hsvHue
        return Qt.hsva(hue < 0 ? 0 : hue, hue < 0 ? 0 : Math.max(c.hsvSaturation, 0.8), 0.95, 1)
    }
    // What the light bar shows because of us; "default" shows nothing we know of.
    readonly property color shownColor: mode === "theme" ? themeColor : mode === "off" ? "#000000" : "transparent"
    property bool touched: false       // we changed it this session, so "default" needs a restore
    property string error: ""

    function isDualSense(dev) {
        return /dualsense/i.test(dev?.model ?? "")
    }

    function load() {}

    function setMode(newMode) {
        Config.options.gamepad.lightMode = newMode
    }

    function apply() {
        if (!root.available) return
        let args = null
        if (root.mode === "theme") {
            const c = root.themeColor
            args = ["set", Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)]
        } else if (root.mode === "off") {
            args = ["off"]
        } else if (root.touched) {
            args = ["restore"]
        }
        if (args === null) return
        root.touched = root.mode !== "default"
        root.pending = ["python3", root.scriptPath].concat(args.map(String))
        if (!proc.running) root.runPending()
    }

    property var pending: null
    function runPending() {
        if (root.pending === null) return
        proc.command = root.pending
        root.pending = null
        proc.running = true
    }

    Process {
        id: proc
        stdout: SplitParser {
            onRead: line => {
                try {
                    const msg = JSON.parse(line)
                    root.error = msg.ok ? "" : (msg.error ?? "failed")
                } catch (e) {}
            }
        }
        onExited: root.runPending()
    }

    Timer {
        id: debounce
        interval: 600
        onTriggered: root.apply()
    }
    // A controller that just connected is still running its own start-up
    // animation and colour, so apply again once that is over.
    Timer {
        id: settleShort
        interval: 2500
        onTriggered: root.apply()
    }
    Timer {
        id: settleLong
        interval: 7000
        onTriggered: root.apply()
    }

    onModeChanged: debounce.restart()
    onThemeColorChanged: if (root.mode === "theme") debounce.restart()
    onAvailableChanged: {
        if (!root.available) return
        settleShort.restart()
        settleLong.restart()
    }
    Component.onCompleted: if (root.available) settleShort.restart()
}
