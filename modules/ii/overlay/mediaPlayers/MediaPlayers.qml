pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

// Overlay widget: every media player that is open right now (MPRIS), with a chip per app
// (icon + name) to switch between them, and previous / play-pause / next + volume for
// the selected one. Everything is reachable with a controller (see OverlayGamepadNavigator).
StyledOverlayWidget {
    id: root
    title: Translation.tr("Media players")
    minimumWidth: 330
    minimumHeight: 250

    readonly property list<MprisPlayer> players: MprisController.players
    // Selected player, remembered by its D-Bus name so it survives list changes
    property string selectedBus: ""
    readonly property MprisPlayer selected: {
        const list = root.players;
        const bySelection = list.find(p => p.dbusName === root.selectedBus);
        if (bySelection) return bySelection;
        const active = MprisController.activePlayer;
        if (active && list.includes(active)) return active;
        return list.length > 0 ? list[0] : null;
    }

    function playerName(player) {
        return player?.identity || player?.desktopEntry || Translation.tr("Player");
    }
    function playerIcon(player) {
        const candidates = [player?.desktopEntry ?? "", player?.identity ?? "", (player?.dbusName ?? "").replace("org.mpris.MediaPlayer2.", "").split(".")[0]];
        for (const c of candidates) {
            if (!c) continue;
            const icon = AppSearch.guessIcon(c);
            if (AppSearch.iconExists(icon)) return SystemAppearance.iconPath(icon, "multimedia-player");
        }
        return SystemAppearance.iconPath("multimedia-player", "image-missing");
    }

    // ---- volume: the app's audio stream in PipeWire (works for every app); falls back to
    // the player's own MPRIS volume when no stream is found (e.g. paused before any sound)
    readonly property var streamNodes: {
        const sel = root.selected;
        if (!sel) return [];
        const keys = [sel.desktopEntry, sel.identity, (sel.dbusName ?? "").replace("org.mpris.MediaPlayer2.", "").split(".")[0]]
            .filter(k => k && k.length > 1).map(k => k.toLowerCase());
        const pidMatch = sel.dbusName?.match(/instance_?(\d+)/);
        const pid = pidMatch ? pidMatch[1] : "";
        return Audio.outputAppNodes.filter(node => {
            const props = node.properties ?? {};
            if (pid && props["application.process.id"] == pid) return true;
            const names = [props["application.name"], props["application.process.binary"], props["application.id"], props["node.name"]]
                .filter(n => n).map(n => String(n).toLowerCase());
            return names.some(n => keys.some(k => n.includes(k) || k.includes(n)));
        });
    }
    PwObjectTracker {
        objects: root.streamNodes
    }
    readonly property bool streamVolume: root.streamNodes.length > 0
    readonly property bool canVolume: root.streamVolume || ((root.selected?.volumeSupported ?? false) && (root.selected?.canControl ?? false))
    readonly property real volume: root.streamVolume ? (root.streamNodes[0].audio?.volume ?? 0) : (root.selected?.volume ?? 0)
    function setVolume(v) {
        v = Math.max(0, Math.min(1, v));
        if (root.streamVolume) {
            for (const node of root.streamNodes) if (node.audio) node.audio.volume = v;
        } else if (root.selected && root.canVolume) {
            root.selected.volume = v;
        }
    }

    contentItem: OverlayBackground {
        id: background
        radius: root.contentRadius
        property real padding: 10

        ColumnLayout {
            anchors {
                fill: parent
                margins: background.padding
            }
            spacing: 10

            // ---- One chip per open player
            Flow {
                Layout.fillWidth: true
                visible: root.players.length > 0
                spacing: 6

                Repeater {
                    model: root.players
                    delegate: RippleButton {
                        id: chip
                        required property MprisPlayer modelData
                        readonly property bool isSelected: root.selected === chip.modelData
                        implicitHeight: 34
                        implicitWidth: chipRow.implicitWidth + 22
                        buttonRadius: height / 2
                        toggled: chip.isSelected
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        colRipple: Appearance.colors.colLayer3Active
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        colRippleToggled: Appearance.colors.colSecondaryContainerActive
                        onClicked: root.selectedBus = chip.modelData.dbusName
                        contentItem: Item {
                            RowLayout {
                                id: chipRow
                                anchors.centerIn: parent
                                spacing: 6
                                IconImage {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitSize: 20
                                    source: root.playerIcon(chip.modelData)
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.maximumWidth: 130
                                    elide: Text.ElideRight
                                    text: root.playerName(chip.modelData)
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: chip.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                }
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: chip.modelData.isPlaying
                                    text: "graphic_eq"
                                    iconSize: 16
                                    color: chip.isSelected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colPrimary
                                }
                            }
                        }
                        StyledToolTip {
                            text: `${root.playerName(chip.modelData)}${chip.modelData.trackTitle ? " • " + chip.modelData.trackTitle : ""}`
                        }
                    }
                }
            }

            // ---- Now playing on the selected player
            RowLayout {
                Layout.fillWidth: true
                visible: root.selected !== null
                spacing: 12

                ClippingRectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer3

                    IconImage {
                        anchors.centerIn: parent
                        visible: cover.status !== Image.Ready
                        implicitSize: 36
                        source: root.playerIcon(root.selected)
                    }
                    Image {
                        id: cover
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: 128
                        sourceSize.height: 128
                        source: root.selected?.trackArtUrl ?? ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selected?.trackTitle || Translation.tr("Nothing playing")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        visible: text.length > 0
                        text: root.selected?.trackArtist ?? ""
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    RowLayout {
                        spacing: 4
                        IconImage {
                            implicitSize: 14
                            source: root.playerIcon(root.selected)
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: root.playerName(root.selected)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // ---- Previous / play-pause / next
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: root.selected !== null
                spacing: 10

                ControlButton {
                    symbol: "skip_previous"
                    enabled: root.selected?.canGoPrevious ?? false
                    onClicked: root.selected.previous()
                }
                ControlButton {
                    big: true
                    symbol: (root.selected?.isPlaying ?? false) ? "pause" : "play_arrow"
                    enabled: root.selected?.canTogglePlaying ?? false
                    onClicked: root.selected.togglePlaying()
                }
                ControlButton {
                    symbol: "skip_next"
                    enabled: root.selected?.canGoNext ?? false
                    onClicked: root.selected.next()
                }
            }

            // ---- Volume of the selected player
            RowLayout {
                Layout.fillWidth: true
                visible: root.selected !== null
                spacing: 6
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: !root.canVolume ? "volume_off" : (root.volume < 0.01 ? "volume_mute" : (root.volume < 0.5 ? "volume_down" : "volume_up"))
                    iconSize: 22
                    color: Appearance.colors.colOnLayer1
                }
                StyledSlider {
                    id: volumeSlider
                    Layout.fillWidth: true
                    enabled: root.canVolume
                    configuration: StyledSlider.Configuration.S
                    from: 0
                    to: 1
                    stepSize: 0.05
                    value: root.volume
                    onMoved: root.setVolume(value)
                }
            }

            // ---- Empty state
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.players.length === 0
                spacing: 6
                Item { Layout.fillHeight: true }
                MaterialShapeWrappedMaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "music_off"
                    iconSize: 40
                    padding: 14
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No media playing")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Open a music or video app to control it here")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                Item { Layout.fillHeight: true }
            }

            Item {
                Layout.fillHeight: true
                visible: root.players.length > 0
            }
        }
    }

    component ControlButton: RippleButton {
        id: controlButton
        property string symbol
        property bool big: false
        implicitWidth: big ? 56 : 44
        implicitHeight: big ? 56 : 44
        buttonRadius: big ? Appearance.rounding.normal : height / 2
        colBackground: big ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
        colBackgroundHover: big ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer3Hover
        colRipple: big ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer3Active
        opacity: enabled ? 1 : 0.4
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: controlButton.symbol
            iconSize: controlButton.big ? 30 : 24
            fill: 1
            color: controlButton.big ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer3
        }
    }
}
