pragma Singleton
import qs
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * MEGA cloud state from MEGAcmd (scripts/cloud/mega_status.py), shown next to the PC's
 * drives in the cheat sheet's System tab (Super+/).
 * Polls every few minutes, every few seconds while something is syncing. Read-only:
 * logging in is done by the user in a terminal (`mega-login <email>`).
 */
Singleton {
    id: root

    property bool installed: true
    property bool loggedIn: false
    property bool loaded: false
    property string status: "offline"      // synced | syncing | error | offline | missing
    property real used: 0
    property real total: 0
    property var syncs: []
    property int uploads: 0
    property int downloads: 0
    property int percent: 0
    property int consumers: 0             // views showing the state (polling only while > 0)

    readonly property real usedFraction: total > 0 ? used / total : 0
    readonly property string icon: {
        switch (root.status) {
        case "synced": return "cloud_done"
        case "syncing": return "cloud_sync"
        case "error": return "sync_problem"
        default: return "cloud_off"
        }
    }
    readonly property string stateText: {
        switch (root.status) {
        case "synced": return root.syncs.length > 0 ? Translation.tr("Synced") : Translation.tr("Connected")
        case "syncing": return root.percent > 0 ? Translation.tr("Syncing · %1%").arg(root.percent) : Translation.tr("Syncing")
        case "error": return Translation.tr("Sync problem")
        case "missing": return Translation.tr("MEGAcmd not installed")
        default: return Translation.tr("Not logged in")
        }
    }
    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/cloud/mega_status.py`)
    readonly property string megaWebappId: (Webapps.items.find(item => /^https?:\/\/(www\.)?mega\.(nz|io)(\/|$)/.test(item.url ?? "")) ?? {}).id ?? ""

    function formatSize(bytes) {
        const units = ["B", "KB", "MB", "GB", "TB"]
        let value = Math.max(0, Number(bytes) || 0)
        let i = 0
        while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ }
        return `${value.toFixed(i > 2 && value < 100 ? 1 : 0)} ${units[i]}`
    }

    function refresh() {
        if (!megaProc.running) megaProc.running = true
    }

    // Opens the MEGA webapp (Settings > Services > Webapps), or the site in the browser.
    function openMega() {
        if (root.megaWebappId !== "") Webapps.open(root.megaWebappId)
        else Qt.openUrlExternally("https://mega.nz/fm")
    }

    function openLoginTerminal() {
        Quickshell.execDetached(["kitty", "--hold", "sh", "-c",
            "echo 'MEGA login — type: mega-login your@email (the password is asked here, never by the shell)'; exec $SHELL -i"])
    }

    Timer {
        interval: root.status === "syncing" ? 5000 : 60000
        repeat: true
        triggeredOnStart: true
        running: Config.ready && root.consumers > 0
        onTriggered: root.refresh()
    }

    Process {
        id: megaProc
        command: ["python3", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.installed = d.installed
                    root.loggedIn = d.loggedIn
                    root.status = d.state
                    root.used = d.used
                    root.total = d.total
                    root.syncs = d.syncs
                    root.uploads = d.uploads
                    root.downloads = d.downloads
                    root.percent = d.percent
                    root.loaded = true
                } catch (e) {
                    console.warn("[MegaCloud]", e)
                }
            }
        }
    }
}
