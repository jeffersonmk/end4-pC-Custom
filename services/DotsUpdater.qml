pragma Singleton

import qs
import qs.modules.common.functions
import QtQuick
import Quickshell

Singleton {
    id: root

    function runSystemUpdate() {
        Quickshell.execDetached([
            "kitty", "--hold",
            "fish", "-i", "-l", "-c",
            "yay -Syu --combinedupgrade=false"
        ])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }

    // Repository this fork is updated from
    readonly property string dotsRepoUrl: "https://github.com/jeffersonmk/end4-pC-Custom.git"

    function runUpdateDots() {
        // Works for any install folder name: update the folder this shell runs from
        const shellDir = FileUtils.trimFileProtocol(Quickshell.shellPath("")).replace(/\/+$/, "");
        const updateScript = `
            set -e
            SHELL_DIR='${StringUtils.shellSingleQuoteEscape(shellDir)}'
            REPO='${root.dotsRepoUrl}'

            # Download to temp first
            rm -rf "$SHELL_DIR-tmp"
            git clone "$REPO" "$SHELL_DIR-tmp"

            # Apply update
            rm -rf "$SHELL_DIR-old"
            [ -d "$SHELL_DIR" ] && mv "$SHELL_DIR" "$SHELL_DIR-old"
            mv "$SHELL_DIR-tmp" "$SHELL_DIR"

            # Reload
            killall qs 2>/dev/null || true
            sleep 0.5
            setsid qs -p "$SHELL_DIR" >/tmp/qs.log 2>&1 < /dev/null &
            disown

            # Cleanup
            rm -rf "$SHELL_DIR-old"
        `

        Quickshell.execDetached(["kitty", "--hold", "bash", "-c", updateScript])
        Qt.callLater(() => GlobalStates.settingsOpen = false)
    }
}
