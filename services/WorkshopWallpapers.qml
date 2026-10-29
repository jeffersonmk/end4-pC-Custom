pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wallpaper Engine Steam Workshop (app 431960), through scripts/workshop/workshop.py.
 *  - online:    browse/search the public Workshop pages (no login, no API key)
 *  - installed: video wallpapers Steam already downloaded (after you subscribe)
 * The content rating filter (workshopMature) is applied by the script itself, so
 * Questionable/Mature items never reach the UI while it is off.
 */
Singleton {
    id: root

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/workshop/workshop.py`)

    // Settings (persisted)
    readonly property bool mature: Config.options.wallpaperSelector.workshopMature
    readonly property string mode: Config.options.wallpaperSelector.workshopMode   // "online" | "installed"
    readonly property string sort: Config.options.wallpaperSelector.workshopSort   // trend | recent | popular | updated
    readonly property int days: Config.options.wallpaperSelector.workshopDays
    readonly property string tag: Config.options.wallpaperSelector.workshopTag

    // State
    property bool fetching: false
    property var results: []          // online page or installed list
    property var installedIds: ({})   // id -> local video path, for "already downloaded" marks
    property string lastError: ""
    property string query: ""
    property int page: 1
    property int totalPages: 1
    property int total: 0
    property var skipped: ({})
    property bool installedLoaded: false

    signal loaded()

    function setMature(value) {
        Config.options.wallpaperSelector.workshopMature = value
        refresh()
    }
    function setMode(value) {
        Config.options.wallpaperSelector.workshopMode = value
        root.query = ""
        refresh()
    }
    function setSort(value) { Config.options.wallpaperSelector.workshopSort = value; root.query = ""; goto(1) }
    function setDays(value) { Config.options.wallpaperSelector.workshopDays = value; goto(1) }
    function setTag(value) { Config.options.wallpaperSelector.workshopTag = value; goto(1) }

    function refresh() { goto(1) }
    function nextPage() { if (root.page < root.totalPages) goto(root.page + 1) }
    function previousPage() { if (root.page > 1) goto(root.page - 1) }
    function search(text) { root.query = text.trim(); goto(1) }

    function goto(p) {
        if (root.mode === "installed") {
            root.page = 1
            root.totalPages = 1
            run(["local"])
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
            root.pendingRequest = { args: args, mode: root.mode }
            return
        }
        start({ args: args, mode: root.mode })
    }

    function start(req) {
        fetchProc.mode = req.mode
        fetchProc.command = ["python3", root.scriptPath].concat(req.args)
        fetchProc.running = true
    }

    // Refresh the "already downloaded" marks without touching the visible list
    function refreshInstalled() {
        if (!statusProc.running) statusProc.running = true
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

    Process {
        id: fetchProc
        property string mode: "online"
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
                root.skipped = data.skipped ?? ({})
                if (fetchProc.mode === "installed") {
                    root.installedLoaded = true
                    const map = {}
                    for (const it of data.items) map[it.id] = it.file
                    root.installedIds = map
                }
                root.loaded()
            }
        }
    }

    // Separate process so "installed" marks work while browsing online
    Process {
        id: statusProc
        command: ["python3", root.scriptPath, "local", "--mature"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                try {
                    const d = JSON.parse(statusOut.text)
                    const map = {}
                    for (const it of d.items ?? []) map[it.id] = it.file
                    root.installedIds = map
                } catch (e) {}
            }
        }
    }
}
