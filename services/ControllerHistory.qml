pragma Singleton
pragma ComponentBehavior: Bound

import "../modules/common/functions/batteryHistory.js" as History
import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import QtQuick

// Battery level history of game controllers, kept on disk so the hover card can
// draw a graph and estimate the remaining time before a new session has data.
Singleton {
    id: root

    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/user/controller_battery_history.json`)
    property var data: ({})        // { key: [{t, p, s, g?}] }
    property int revision: 0       // bumped on every change, for bindings

    property bool loaded: false
    property var queued: []        // readings that arrived before the file was read

    function record(key, pct, stateKey, sessionStart) {
        const reading = { key: key, pct: pct, stateKey: stateKey, sessionStart: sessionStart, t: Date.now() }
        if (!root.loaded) {
            root.queued = root.queued.concat([reading])
            return
        }
        root.apply(reading)
    }

    function apply(reading) {
        const key = reading.key
        const before = root.data[key] ?? []
        const after = History.addPoint(before, reading.t, Math.round(reading.pct * 1000) / 1000, reading.stateKey, reading.sessionStart)
        if (after === before) return
        const next = Object.assign({}, root.data)
        next[key] = after
        root.data = next
        root.revision++
        saveTimer.restart()
    }

    function chart(key, spanMs) {
        return History.chart(root.data[key] ?? [], Date.now(), spanMs)
    }

    // Seconds until empty / full from the measured steps, 0 when unknown.
    function estimate(key, charging, pct) {
        return History.estimate(root.data[key] ?? [], charging, pct)
    }

    function finishLoading() {
        if (root.loaded) return
        root.loaded = true
        const pendingReadings = root.queued
        root.queued = []
        root.revision++
        for (const reading of pendingReadings) root.apply(reading)
    }

    // Safety net in case the file backend never answers
    Timer {
        interval: 3000
        running: true
        onTriggered: root.finishLoading()
    }

    Timer {
        id: saveTimer
        interval: 4000
        onTriggered: file.setText(JSON.stringify(root.data))
    }

    FileView {
        id: file
        path: root.filePath
        blockLoading: true
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                const parsed = JSON.parse(file.text())
                if (parsed && typeof parsed === "object") root.data = parsed
            } catch (e) {
                console.warn("[ControllerHistory] ignoring unreadable history file:", e)
            }
            root.finishLoading()
        }
        onLoadFailed: root.finishLoading()    // no file yet: start empty
    }
}
