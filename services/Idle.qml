pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Keep system awake (idle inhibitor).
 */
Singleton {
    id: root

    property bool inhibit: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.inhibit = Persistent.states.idle.inhibit;
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // The inhibitor needs a mapped surface. A single window dies for good when its
    // monitor disappears (monitor powered off / sleeping / input switch), silently
    // dropping the inhibitor so hypridle locks, blanks and suspends anyway.
    // One tiny window per screen is recreated whenever screens come back.
    Variants {
        model: root.inhibit ? Quickshell.screens : []

        delegate: Scope {
            id: perScreen
            required property ShellScreen modelData

            IdleInhibitor {
                enabled: true
                window: PanelWindow {
                    screen: perScreen.modelData
                    WlrLayershell.namespace: "quickshell:idleInhibitor"
                    WlrLayershell.layer: WlrLayer.Background
                    exclusionMode: ExclusionMode.Ignore
                    implicitWidth: 1
                    implicitHeight: 1
                    color: "transparent"
                    anchors {
                        right: true
                        bottom: true
                    }
                    // Not interactable
                    mask: Region {
                        item: null
                    }
                }
            }
        }
    }
}
