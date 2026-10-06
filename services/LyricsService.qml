pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    // The left-sidebar player can show a different player than the "active" one
    // (e.g. a paused music app while a browser video plays). It pins its player here
    // so the lyrics always match what is on screen.
    property MprisPlayer pinnedPlayer: null
    readonly property MprisPlayer activePlayer: root.pinnedPlayer ?? MprisController.activePlayer

    property var lyricsLines: []
    property int activeIndex: -1
    property string status: "loading"
    property var slots: ["", "", "", "", "", "", ""]

    readonly property int before: 3
    readonly property int after:  3
    readonly property int total:  7

    function buildSlots(idx) {
        let result = []
        for (let i = 0; i < root.total; i++) {
            let lineIdx = idx - root.before + i
            if (lineIdx >= 0 && lineIdx < root.lyricsLines.length)
                result.push(root.lyricsLines[lineIdx].text || "♪")
            else
                result.push("")
        }
        return result
    }

    readonly property bool playing: root.activePlayer?.isPlaying ?? false
    // status: "loading" | "ok" (synced) | "plain" (unsynced, estimated times) | "not_found" | "no_info"
    readonly property bool synced: (root.status === "ok" || root.status === "plain") && root.lyricsLines.length > 0
    readonly property bool unsynced: root.status === "plain"
    readonly property real leadSeconds: 0.15

    property real basePosition: 0
    property real baseTime: Date.now()

    function currentPosition() {
        return root.playing ? root.basePosition + (Date.now() - root.baseTime) / 1000 : root.basePosition
    }

    function resync() {
        if (!root.activePlayer) return
        root.activePlayer.positionChanged()
        readPositionTimer.restart()
    }

    function indexAt(pos) {
        const lines = root.lyricsLines
        let low = 0
        let high = lines.length - 1
        let result = -1
        while (low <= high) {
            const mid = (low + high) >> 1
            if (lines[mid].time <= pos) {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    function update() {
        boundaryTimer.stop()
        if (!root.synced) return
        const idx = root.indexAt(root.currentPosition() + root.leadSeconds)
        if (idx !== root.activeIndex) {
            root.activeIndex = idx
            root.slots = root.buildSlots(idx)
        }
        const next = root.lyricsLines[idx + 1]
        if (!root.playing || !next) return
        const delay = (next.time - root.leadSeconds - root.currentPosition()) * 1000
        boundaryTimer.interval = Math.max(1, Math.ceil(delay))
        boundaryTimer.start()
    }

    Timer {
        id: readPositionTimer
        interval: 80
        onTriggered: {
            root.basePosition = root.activePlayer?.position ?? 0
            root.baseTime = Date.now()
            root.update()
        }
    }

    Timer {
        id: boundaryTimer
        onTriggered: root.update()
    }

    Timer {
        id: driftTimer
        interval: 4000
        repeat: true
        running: root.synced && root.playing
        onTriggered: root.resync()
    }

    Process {
        id: lyricsProc
        running: false
        stdout: SplitParser {
            onRead: data => {
                const trimmed = data.trim()
                if (trimmed === "not_found") { root.status = "not_found"; return }
                if (trimmed === "no_info")   { root.status = "no_info";   return }

                const parts = trimmed.split("§")
                if (parts.length < 3) return
                const kind = parts[parts.length - 1].trim()
                if (kind !== "ok" && kind !== "plain") return

                let lines = []
                for (let i = 0; i < parts.length - 1; i += 2) {
                    const t = parseFloat(parts[i])
                    const txt = parts[i + 1] || ""
                    if (!isNaN(t)) lines.push({ time: t, text: txt })
                }

                if (lines.length === 0) { root.status = "not_found"; return }

                root.lyricsLines = lines
                root.activeIndex = -1
                root.slots = root.buildSlots(-1)
                root.status = kind
                root.resync()
            }
        }
    }

    // Players often publish title, artist, album and length in separate updates
    // (Feishin sends the length a moment after the title). Wait for things to settle
    // so the lookup uses the right track length.
    Timer {
        id: restartDebounce
        interval: 350
        onTriggered: root.restartLyrics()
    }

    property string lastQuery: ""

    function scheduleRestart() {
        restartDebounce.restart()
    }

    // Manual retry from the UI: skip the cache
    function retry() {
        root.forceRefresh = true
        root.restartLyrics()
    }
    property bool forceRefresh: false

    function restartLyrics() {
        restartDebounce.stop()
        lyricsProc.running = false
        boundaryTimer.stop()
        root.lyricsLines = []
        root.activeIndex = -1
        root.slots = ["", "", "", "", "", "", ""]
        root.status = "loading"

        const title    = root.activePlayer?.trackTitle  ?? ""
        const artist   = root.activePlayer?.trackArtist ?? ""
        const album    = root.activePlayer?.trackAlbum  ?? ""
        const duration = root.activePlayer?.length       ?? 0

        if (!title || !artist) { root.status = "no_info"; root.lastQuery = ""; return }

        root.lastQuery = [title, artist, album, Math.round(duration)].join("\u001f")
        lyricsProc.command = [
            "python3",
            `${Directories.scriptPath}/lyrics/lyrics.py`,
            title, artist, String(Math.round(duration)), album
        ].concat(root.forceRefresh ? ["--refresh"] : [])
        root.forceRefresh = false
        lyricsProc.running = true
    }

    function queryChanged() {
        const p = root.activePlayer
        const q = [p?.trackTitle ?? "", p?.trackArtist ?? "", p?.trackAlbum ?? "", Math.round(p?.length ?? 0)].join("\u001f")
        return q !== root.lastQuery
    }

    onActivePlayerChanged: root.scheduleRestart()

    Connections {
        target: root.activePlayer
        function onTrackTitleChanged()  { root.scheduleRestart() }
        function onTrackArtistChanged() { if (root.queryChanged()) root.scheduleRestart() }
        function onTrackAlbumChanged()  { if (root.queryChanged()) root.scheduleRestart() }
        // A late length update (or a wrong one at track start) would pick the wrong version
        function onLengthChanged()      { if (root.queryChanged() && root.status !== "ok") root.scheduleRestart() }
        function onPlaybackStateChanged() { root.resync() }
    }

    Component.onCompleted: root.restartLyrics()
}