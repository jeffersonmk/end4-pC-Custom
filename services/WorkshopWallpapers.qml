pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wallpaper Engine Steam Workshop (app 431960), through scripts/workshop/workshop.py.
 *  - online:  browse/search the public Workshop pages (no login, no API key)
 *  - library: everything Steam knows you are subscribed to, split into downloaded and
 *             not downloaded (read from Steam's own appworkshop_431960.acf), with delete
 * The content rating filter (workshopMature) is applied by the script itself, so
 * Questionable/Mature items never reach the UI while it is off.
 */
Singleton {
    id: root

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/workshop/workshop.py`)

    // Settings (persisted)
    readonly property bool mature: Config.options.wallpaperSelector.workshopMature
    readonly property string mode: Config.options.wallpaperSelector.workshopMode   // "online" | "library"
    readonly property bool libraryMode: root.mode !== "online"
    readonly property string sort: Config.options.wallpaperSelector.workshopSort   // trend | recent | popular | updated
    readonly property int days: Config.options.wallpaperSelector.workshopDays
    readonly property string tag: Config.options.wallpaperSelector.workshopTag

    // State
    property bool fetching: false
    property var results: []          // online page, or the whole library
    property var libraryInfo: ({})    // id -> { downloaded, supported, file, subscribed }, for marks while browsing online
    property string lastError: ""
    property string query: ""         // online search text
    property int page: 1
    property int totalPages: 1
    property int total: 0
    property int hiddenByRating: 0

    // Library view
    property string libraryFilter: "all"   // all | downloaded | pending | unsupported
    property string originFilter: "all"    // all | workshop | mine | folder | app
    property string libraryQuery: ""
    readonly property var originList: ["workshop", "mine", "folder", "app"]
    function countOrigin(o) { return root.results.filter(i => i.origin === o).length }
    readonly property var downloadedItems: root.results.filter(i => i.downloaded)
    // What "delete" can free: only Workshop downloads, never your own files or the app's
    readonly property var deletableItems: root.results.filter(i => i.downloaded && i.origin === "workshop")
    readonly property var pendingItems: root.results.filter(i => !i.downloaded)
    readonly property var unsupportedItems: root.results.filter(i => !i.supported)
    readonly property int downloadedBytes: root.deletableItems.reduce((a, i) => a + (i.size || 0), 0)
    readonly property var shown: {
        if (!root.libraryMode) return root.results
        const q = root.libraryQuery.trim().toLowerCase()
        return root.results.filter(i => {
            if (root.originFilter !== "all" && i.origin !== root.originFilter) return false
            if (root.libraryFilter === "downloaded" && !i.downloaded) return false
            if (root.libraryFilter === "pending" && i.downloaded) return false
            if (root.libraryFilter === "unsupported" && i.supported) return false
            return q.length === 0 || i.title.toLowerCase().includes(q)
        })
    }

    // Requirements checklist
    property var requirements: []
    property int requiredFailing: 0
    property bool requirementsLoaded: false

    // Short message after deleting
    property string notice: ""

    signal loaded()

    function setMature(value) {
        Config.options.wallpaperSelector.workshopMature = value
        refresh()
    }
    function setMode(value) {
        Config.options.wallpaperSelector.workshopMode = value
        root.query = ""
        root.results = []
        refresh()
    }
    function setSort(value) { Config.options.wallpaperSelector.workshopSort = value; root.query = ""; goto(1) }
    function setDays(value) { Config.options.wallpaperSelector.workshopDays = value; goto(1) }
    function setTag(value) { Config.options.wallpaperSelector.workshopTag = value; goto(1) }

    function refresh() { goto(1) }
    function nextPage() { if (root.page < root.totalPages) goto(root.page + 1) }
    function previousPage() { if (root.page > 1) goto(root.page - 1) }
    function search(text) {
        if (root.libraryMode) { root.libraryQuery = text; return }
        root.query = text.trim()
        goto(1)
    }

    function goto(p) {
        if (root.libraryMode) {
            root.page = 1
            root.totalPages = 1
            const args = ["library"]
            const extra = Config.options.wallpaperSelector.liveWallpapersPath ?? ""
            if (extra.length > 0) args.push("--extra-dir", extra)
            run(args)
            return
        }
        const args = ["browse", "--page", String(p), "--sort", root.sort, "--days", String(root.days)]
        if (root.query.length > 0) args.push("--query", root.query)
        if (root.tag.length > 0) args.push("--tag", root.tag)
        root.page = p
        run(args)
    }

    // One helper process at a time. A request made while another is running waits for it
    // (its answer is dropped), so a slow old answer can never overwrite a newer one.
    property var pendingRequest: null

    function run(args) {
        if (root.mature) args.push("--mature")
        root.fetching = true
        root.lastError = ""
        if (fetchProc.running) {
            root.pendingRequest = { args: args, libraryMode: root.libraryMode }
            return
        }
        start({ args: args, libraryMode: root.libraryMode })
    }

    function start(req) {
        fetchProc.libraryMode = req.libraryMode
        fetchProc.command = ["python3", root.scriptPath].concat(req.args)
        fetchProc.running = true
    }

    function indexLibrary(items) {
        const map = {}
        for (const it of items) map[it.id] = { downloaded: it.downloaded, supported: it.supported, file: it.file, subscribed: it.subscribed, dir: it.dir, size: it.size, origin: it.origin }
        root.libraryInfo = map
    }

    // Refresh the marks (downloaded / subscribed) without touching the visible list
    function refreshLibraryInfo() {
        if (!statusProc.running) statusProc.running = true
    }

    function checkRequirements() {
        if (!reqProc.running) reqProc.running = true
    }

    function isCurrentWallpaper(item) {
        const cur = Config.options.background.wallpaperPath ?? ""
        return item.dir && item.dir.length > 0 && cur.startsWith(item.dir + "/")
    }

    // Delete the downloaded folders of these items (ids). Nothing else is touched.
    function deleteItems(ids) {
        if (ids.length === 0 || deleteProc.running) return
        deleteProc.command = ["python3", root.scriptPath, "delete"].concat(ids)
        deleteProc.running = true
    }

    function subscribe(item) {
        // The Steam client does the downloading; the user clicks Subscribe on the page it opens.
        Quickshell.execDetached(["xdg-open", `steam://url/CommunityFilePage/${item.id}`])
    }
    function openInBrowser(item) {
        Qt.openUrlExternally(`https://steamcommunity.com/sharedfiles/filedetails/?id=${item.id}`)
    }

    function previewSource(item) {
        if (!item.preview) return ""
        if (item.preview.startsWith("/")) return "file://" + item.preview
        // Steam CDN: ask for a small letterboxed copy instead of the full-size image
        return item.preview + (item.preview.includes("?") ? "&" : "?") + "imw=480&imh=270&ima=fit&impolicy=Letterbox"
    }

    function formatBytes(n) {
        if (!n || n <= 0) return "0 B"
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++ }
        return (i === 0 ? n.toFixed(0) : n.toFixed(n >= 100 ? 0 : 1)) + " " + u[i]
    }

    function say(text) {
        root.notice = text
        noticeTimer.restart()
    }

    Timer {
        id: noticeTimer
        interval: 7000
        onTriggered: root.notice = ""
    }

    Process {
        id: fetchProc
        property bool libraryMode: false
        stdout: StdioCollector {
            id: fetchOut
            onStreamFinished: {
                if (root.pendingRequest) { // stale answer, a newer request is waiting
                    const req = root.pendingRequest
                    root.pendingRequest = null
                    Qt.callLater(() => root.start(req))
                    return
                }
                root.fetching = false
                let data = null
                try { data = JSON.parse(fetchOut.text) } catch (e) { data = null }
                if (!data || !data.ok) {
                    root.results = []
                    root.lastError = data?.error ?? Translation.tr("Could not run the Workshop helper (is python3 installed?)")
                    root.loaded()
                    return
                }
                root.results = data.items
                root.total = data.total ?? data.items.length
                root.totalPages = data.totalPages ?? 1
                root.hiddenByRating = data.hiddenByRating ?? 0
                if (fetchProc.libraryMode) root.indexLibrary(data.items)
                root.loaded()
            }
        }
    }

    // Separate process so the marks work while browsing online
    Process {
        id: statusProc
        command: ["python3", root.scriptPath, "library", "--mature"].concat(
            (Config.options.wallpaperSelector.liveWallpapersPath ?? "").length > 0 ? ["--extra-dir", Config.options.wallpaperSelector.liveWallpapersPath] : [])
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                try { root.indexLibrary(JSON.parse(statusOut.text).items ?? []) } catch (e) {}
            }
        }
    }

    Process {
        id: reqProc
        command: ["python3", root.scriptPath, "requirements"]
        stdout: StdioCollector {
            id: reqOut
            onStreamFinished: {
                try {
                    const d = JSON.parse(reqOut.text)
                    root.requirements = d.checks
                    root.requiredFailing = d.requiredFailing
                    root.requirementsLoaded = true
                } catch (e) {}
            }
        }
    }

    Process {
        id: deleteProc
        stdout: StdioCollector {
            id: deleteOut
            onStreamFinished: {
                let d = null
                try { d = JSON.parse(deleteOut.text) } catch (e) { d = null }
                if (!d) {
                    root.notice = Translation.tr("Could not delete (the helper failed)")
                } else if (d.failed.length > 0 && d.deleted.length === 0) {
                    root.notice = Translation.tr("Could not delete: %1").arg(d.failed[0].error)
                } else {
                    root.notice = Translation.tr("Deleted %1 wallpaper(s), freed %2").arg(d.deleted.length).arg(root.formatBytes(d.freed))
                        + (d.failed.length > 0 ? " " + Translation.tr("(%1 failed)").arg(d.failed.length) : "")
                }
                noticeTimer.restart()
                root.refresh()
                root.refreshLibraryInfo()
            }
        }
    }
}
