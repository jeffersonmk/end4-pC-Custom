pragma Singleton

import QtQuick
import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root
    signal gammaChangeAttempt()

    readonly property real gammaLowerLimit: 25
    readonly property bool isNiri: WM.compositor === "niri"

    property string from: Config.options?.light?.night?.from ?? "19:00"
    property string to: Config.options?.light?.night?.to ?? "06:30"
    property bool automatic: (Config.options?.light?.night?.automatic ?? false) && (Config?.ready ?? true)
    property int colorTemperature: Config.options?.light?.night?.colorTemperature ?? 5000
    property int gamma: 100
    property bool shouldBeOn
    property bool firstEvaluation: true
    property bool temperatureActive: false

    property int fromHour: Number(from.split(":")[0])
    property int fromMinute: Number(from.split(":")[1])
    property int toHour: Number(to.split(":")[0])
    property int toMinute: Number(to.split(":")[1])

    property int clockHour: DateTime.clock.hours
    property int clockMinute: DateTime.clock.minutes

    property var manualActive
    property int manualActiveHour
    property int manualActiveMinute

    onClockMinuteChanged: reEvaluate()
    // The night light always starts off (PC boot or shell restart), even inside the
    // automatic schedule. Auto mode takes over again once the schedule is outside its
    // window (so it turns on at the next start time), or as soon as you toggle it.
    property bool startupOff: false

    onAutomaticChanged: {
        root.manualActive = undefined;
        root.firstEvaluation = true;
        reEvaluate();
    }

    function inBetween(t, from, to) {
        if (from < to) {
            return (t >= from && t <= to);
        } else {
            return (t >= from || t <= to);
        }
    }

    function reEvaluate() {
        const t = clockHour * 60 + clockMinute;
        const from = fromHour * 60 + fromMinute;
        const to = toHour * 60 + toMinute;
        const manualActive = manualActiveHour * 60 + manualActiveMinute;

        if (root.manualActive !== undefined && (inBetween(from, manualActive, t) || inBetween(to, manualActive, t))) {
            root.manualActive = undefined;
        }
        root.shouldBeOn = inBetween(t, from, to);

        if (firstEvaluation) {
            firstEvaluation = false;
            return;
        }
        root.ensureState();
    }

    onShouldBeOnChanged: {
        if (!root.firstEvaluation)
            root.ensureState();
    }

    function ensureState() {
        if (!root.automatic || root.manualActive !== undefined)
            return;
        if (root.startupOff) {
            if (root.shouldBeOn) return;
            root.startupOff = false;
        }
        if (root.shouldBeOn) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    function startHyprsunset() {
        if (root.isNiri) return;
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset`]);
    }

    function load() {
        if (root.isNiri) {
            root.disableTemperature();
            return;
        }
        Quickshell.execDetached(["bash", "-c", `pidof hyprsunset || hyprsunset & disown; sleep 0.3; hyprctl hyprsunset identity`]);
        root.temperatureActive = false;
        root.startupOff = true;
    }

    function enableTemperature() {
        if (root.isNiri) {
            root.startNiriSunset(root.colorTemperature);
        } else {
            root.startHyprsunset();
            Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset temperature ${root.colorTemperature}`]);
        }
        root.temperatureActive = true;
    }

    function disableTemperature() {
        if (root.isNiri) {
            root.stopNiriSunset();
        } else {
            Quickshell.execDetached(["hyprctl", "hyprsunset", "identity"]);
        }
        root.temperatureActive = false;
    }

    function setGamma(gamma) {
        root.gamma = Math.max(root.gammaLowerLimit, Math.min(100, gamma));
        root.gammaChangeAttempt();

        if (root.isNiri) {
            return;
        }
        root.startHyprsunset();
        Quickshell.execDetached(["bash", "-c", `hyprctl hyprsunset gamma ${root.gamma}`]);
    }

    function startNiriSunset(temp) {
        const low = temp;
        const high = temp + 50;
        Quickshell.execDetached(["bash", "-c",
            `pkill -x wlsunset; sleep 0.05; wlsunset -T ${high} -t ${low} -S 23:59 -s 00:00 -d 1 & disown`]);
    }

    function stopNiriSunset() {
        Quickshell.execDetached(["bash", "-c", "pkill -x wlsunset"]);
    }

    function fetchState() {
        if (root.isNiri) {
            niriFetchProc.running = true;
        }
        // Hyprland: the shell's own state is the source of truth. load() resets the
        // screen to normal colors at startup, and hyprsunset keeps reporting the last
        // temperature (e.g. 5000) even after "identity", so asking it would show the
        // night light as ON when it isn't.
    }

    Process {
        id: fetchProc
        running: false
        command: ["bash", "-c", "hyprctl hyprsunset temperature"]
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const output = stateCollector.text.trim();
                if (output.length == 0 || output.startsWith("Couldn't"))
                    root.temperatureActive = false;
                else
                    root.temperatureActive = (output != "6500");
            }
        }
    }

    Process {
        id: niriFetchProc
        running: false
        command: ["bash", "-c", "pgrep -x wlsunset"]
        stdout: StdioCollector {
            id: niriStateCollector
            onStreamFinished: {
                root.temperatureActive = niriStateCollector.text.trim().length > 0;
            }
        }
    }

    function toggleTemperature(active = undefined) {
        root.startupOff = false;
        if (root.manualActive === undefined) {
            root.manualActive = root.temperatureActive;
            root.manualActiveHour = root.clockHour;
            root.manualActiveMinute = root.clockMinute;
        }

        root.manualActive = active !== undefined ? active : !root.manualActive;
        if (root.manualActive) {
            root.enableTemperature();
        } else {
            root.disableTemperature();
        }
    }

    Connections {
        target: Config.options.light.night
        function onColorTemperatureChanged() {
            if (!root.temperatureActive) return;
            if (root.isNiri) {
                root.startNiriSunset(Config.options.light.night.colorTemperature);
            } else {
                Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", `${Config.options.light.night.colorTemperature}`]);
            }
        }
    }
}
