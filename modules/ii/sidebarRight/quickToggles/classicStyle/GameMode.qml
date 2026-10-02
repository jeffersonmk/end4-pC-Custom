import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import Quickshell.Io

QuickToggleButton {
    id: root
    buttonIcon: "gamepad"
    // Starts off; the real state is read from Hyprland right after (game mode is on
    // only when animations are disabled)
    toggled: false

    onClicked: {
        root.toggled = !root.toggled
        if (root.toggled) {
            Quickshell.execDetached(["bash", "-c", `hyprctl --batch "keyword animations:enabled 0; keyword decoration:shadow:enabled 0; keyword decoration:blur:enabled 0; keyword general:gaps_in 0; keyword general:gaps_out 0; keyword general:border_size 1; keyword decoration:rounding 0; keyword general:allow_tearing 1"`])
        } else {
            Quickshell.execDetached(["hyprctl", "reload"])
        }
    }
    Process {
        id: fetchActiveState
        running: true
        // Newer Hyprland reports this option as {"bool": true} instead of {"int": 1}; the
        // old check only read ".int", failed on null and showed game mode as ON at startup
        command: ["bash", "-c", `hyprctl getoption animations:enabled -j | jq -r 'if has("int") then .int elif has("bool") then (if .bool then 1 else 0 end) else 1 end'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = this.text.trim();
                // Anything unexpected counts as "animations on" = game mode off
                root.toggled = value === "0";
            }
        }
    }
    StyledToolTip {
        text: Translation.tr("Game mode")
    }
}