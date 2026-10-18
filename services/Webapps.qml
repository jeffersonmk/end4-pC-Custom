pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/webapp/webapp.sh`

    property var items: []
    property var browsers: []   // installed Chromium-based browsers: [{id, name, path}]
    property string error: ""
    readonly property bool busy: createProc.running

    function browserName(id) {
        const b = root.browsers.find(item => item.id === id);
        return b ? b.name : (id || "");
    }

    function parseUrls(text) {
        return String(text).split(/[\n,\s]+/).map(line => line.trim()).filter(line => line !== "");
    }

    function refresh() {
        listProc.running = true;
        browsersProc.running = true;
    }

    function create(text) {
        const urls = root.parseUrls(text);
        if (urls.length === 0 || createProc.running) return;
        root.error = "";
        createProc.environment = {
            "WEBAPP_ICON_THEME": SystemAppearance.iconTheme ?? "",
            "WEBAPP_BROWSER": Config.options.webapps.browser ?? "",
            "WEBAPP_ISOLATED": (Config.options.webapps.isolated ?? true) ? "1" : "0"
        };
        createProc.command = ["bash", root.scriptPath, "create", ...urls];
        createProc.running = true;
    }

    function remove(id) {
        removeProc.command = ["bash", root.scriptPath, "remove", id];
        removeProc.running = true;
    }

    function rename(id, name) {
        const clean = (name ?? "").trim();
        if (clean === "") return;
        renameProc.command = ["bash", root.scriptPath, "rename", id, clean];
        renameProc.running = true;
    }

    // Pick an icon: KDE icon chooser (icon theme icons, plus "Browse..." for any image),
    // or a plain image picker when kdialog isn't installed
    function chooseIcon(id) {
        if (chooseIconProc.running) return;
        chooseIconProc.webappId = id;
        chooseIconProc.command = ["bash", "-c",
            'if command -v kdialog >/dev/null 2>&1; then kdialog --title "$1" --geticon Desktop Application; '
            + 'else zenity --file-selection --title="$1" --file-filter="$2 | *.png *.svg *.jpg *.jpeg *.webp *.ico *.bmp"; fi',
            "_", Translation.tr("Choose an icon"), Translation.tr("Images")];
        chooseIconProc.running = true;
    }

    function setIcon(id, icon) {
        const clean = (icon ?? "").trim();
        if (clean === "") return;
        iconProc.command = ["bash", root.scriptPath, "seticon", id, clean];
        iconProc.running = true;
    }

    function resetIcon(id) {
        iconProc.command = ["bash", root.scriptPath, "reseticon", id];
        iconProc.running = true;
    }

    function open(id) {
        openProc.command = ["bash", root.scriptPath, "open", id];
        openProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: listProc
        command: ["bash", root.scriptPath, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.items = JSON.parse(text);
                } catch (e) {
                    root.items = [];
                }
            }
        }
    }

    Process {
        id: browsersProc
        command: ["bash", root.scriptPath, "browsers"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.browsers = JSON.parse(text);
                } catch (e) {
                    root.browsers = [];
                }
            }
        }
    }

    Process {
        id: createProc
        stdout: StdioCollector {
            id: createOut
        }
        onExited: {
            const failures = createOut.text.split("\n").filter(line => line.startsWith("ERR"));
            root.error = failures.map(line => line.replace(/^ERR\s*/, "")).join(", ");
            root.refresh();
        }
    }

    Process {
        id: removeProc
        onExited: root.refresh()
    }

    Process {
        id: renameProc
        stdout: StdioCollector {
            id: renameOut
        }
        onExited: {
            const failure = renameOut.text.split("\n").find(line => line.startsWith("ERR"));
            root.error = failure ? failure.replace(/^ERR\s*/, "") : "";
            root.refresh();
        }
    }

    Process {
        id: openProc
    }

    Process {
        id: chooseIconProc
        property string webappId: ""
        stdout: StdioCollector {
            id: chooseIconOut
        }
        onExited: (exitCode) => {
            const picked = chooseIconOut.text.trim();
            if (exitCode === 0 && picked !== "") root.setIcon(webappId, picked);
        }
    }

    Process {
        id: iconProc
        environment: ({ "WEBAPP_ICON_THEME": SystemAppearance.iconTheme ?? "" })
        stdout: StdioCollector {
            id: iconOut
        }
        onExited: {
            const failure = iconOut.text.split("\n").find(line => line.startsWith("ERR"));
            root.error = failure ? failure.replace(/^ERR\s*/, "") : "";
            root.refresh();
        }
    }
}
