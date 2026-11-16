import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Qt5Compat.GraphicalEffects

Item {
    id: root
    // One row per app: all the PipeWire streams in the group are controlled together
    required property bool isSink
    required property string groupKey
    readonly property list<var> nodes: Audio.appGroupNodes(root.isSink, root.groupKey)
    // The stream that names the row (Wine's "PipeWire ALSA [...]" stream is only a fallback)
    readonly property var node: root.nodes.find(n => !(n.properties["application.name"] ?? "").startsWith("PipeWire ALSA")) ?? root.nodes[0] ?? null
    readonly property bool muted: root.nodes.length > 0 && root.nodes.every(n => n.audio?.muted)
    readonly property real volume: root.nodes.reduce((max, n) => Math.max(max, n.audio?.volume ?? 0), 0)
    visible: root.node !== null
    // Used by the controller overlay (X / □ on a focused slider)
    function toggleMute() {
        const mute = !root.muted;
        for (const n of root.nodes) if (n.audio) n.audio.muted = mute;
        return mute; // PipeWire confirms asynchronously, so root.muted is still stale here
    }
    function setVolume(v) {
        for (const n of root.nodes) if (n.audio) n.audio.volume = v;
    }
    PwObjectTracker {
        objects: root.nodes
    }

    implicitHeight: root.node ? rowLayout.implicitHeight : 0

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        spacing: 6

        MouseArea {
            property real size: 36
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            Layout.preferredWidth: size
            Layout.preferredHeight: size

            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMute()

            hoverEnabled: true
            property bool hovered: containsMouse
            StyledToolTip {
                text: root.muted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
            }

            Image {
                id: iconImg
                anchors.fill: parent
                visible: false
                sourceSize.width: parent.size
                sourceSize.height: parent.size
                source: {
                    let icon;
                    icon = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
                    if (AppSearch.iconExists(icon))
                        return SystemAppearance.iconPath(icon, "image-missing");
                    icon = AppSearch.guessIcon(root.node?.properties["node.name"] ?? "");
                    return SystemAppearance.iconPath(icon, "image-missing");
                }
            }

            Desaturate {
                anchors.fill: iconImg
                source: iconImg
                desaturation: root.muted ? 1.0 : 0.0
                visible: iconImg.source !== ""
                opacity: root.muted ? 0.4 : 1.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 150
                    }
                }
                Behavior on desaturation {
                    NumberAnimation {
                        duration: 150
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.muted
                text: root.isSink ? "volume_off" : "mic_off"
                iconSize: 22
                color: Appearance.colors.colOnLayer1
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: -4

            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                text: {
                    // application.name -> description -> name
                    const app = Audio.appNodeDisplayName(root.node);
                    const media = root.node.properties["media.name"];
                    return (media != undefined && root.nodes.length === 1) ? `${app} • ${media}` : app;
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                StyledSlider {
                    id: slider
                    value: root.volume
                    onMoved: root.setVolume(value)
                    configuration: StyledSlider.Configuration.S

                    // The controller overlay calls this (X / □) on the focused slider
                    function padAction() {
                        return root.toggleMute() ? Translation.tr("Muted") : Translation.tr("Unmuted");
                    }
                    readonly property bool hasPadAction: true
                }

                RippleButton {
                    id: muteButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 32
                    implicitHeight: 32
                    buttonRadius: height / 2
                    toggled: root.muted
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    onClicked: root.toggleMute()

                    StyledToolTip {
                        text: root.muted ? Translation.tr("Click to unmute") : Translation.tr("Click to mute")
                    }
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        iconSize: 20
                        text: root.isSink ? (root.muted ? "volume_off" : "volume_up") : (root.muted ? "mic_off" : "mic")
                        color: root.muted ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
