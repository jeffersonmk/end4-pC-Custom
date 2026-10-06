pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property color textColor: "white"
    property color activeColor: "white"
    property color dimColor: Qt.rgba(1, 1, 1, 0.35)
    property color indicatorColor: Appearance.colors.colPrimaryContainer
    property color indicatorShapeColor: Appearance.colors.colOnPrimaryContainer
    property int textAlignment: Text.AlignLeft
    property real fontScale: 1.0
    property bool animateTransitions: false
    property real lineSpacing: 6

    implicitWidth: 200
    implicitHeight: 200

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        // ── Loading ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "loading"

            MaterialLoadingIndicator {
                anchors.centerIn: parent
                loading: parent.visible
                colBg: root.indicatorColor
                colShape: root.indicatorShapeColor
                implicitSize: 48
            }
        }

        // ── No lyrics / no track info ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "not_found" || LyricsService.status === "no_info"

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: LyricsService.status === "no_info" ? "music_off" : "lyrics"
                    iconSize: 30 * root.fontScale
                    color: root.textColor
                    opacity: 0.45
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: root.textAlignment === Text.AlignLeft ? Text.AlignLeft : Text.AlignHCenter
                    text: LyricsService.status === "no_info"
                        ? Translation.tr("No track info")
                        : Translation.tr("Lyrics not available")
                    font.pixelSize: Appearance.font.pixelSize.small * root.fontScale
                    color: root.textColor
                    opacity: 0.6
                    wrapMode: Text.WordWrap
                }
                RippleButton {
                    Layout.alignment: root.textAlignment === Text.AlignLeft ? Qt.AlignLeft : Qt.AlignHCenter
                    visible: LyricsService.status === "not_found"
                    implicitHeight: 28
                    horizontalPadding: 12
                    buttonRadius: 14
                    colBackground: ColorUtils.transparentize(root.indicatorColor, 0.6)
                    colBackgroundHover: ColorUtils.transparentize(root.indicatorColor, 0.3)
                    onClicked: LyricsService.retry()
                    contentItem: RowLayout {
                        spacing: 4
                        MaterialSymbol { text: "refresh"; iconSize: 16; color: root.textColor }
                        StyledText {
                            text: Translation.tr("Try again")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: root.textColor
                        }
                    }
                }
            }
        }

        // ── Lyrics (synced, or plain lyrics with estimated timing) ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: LyricsService.status === "ok" || LyricsService.status === "plain"
            spacing: root.lineSpacing

            Repeater {
                model: 7
                delegate: StyledText {
                    id: lyricSlot
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: root.textAlignment
                    wrapMode: Text.WordWrap
                    text: LyricsService.slots[index] ?? ""
                    readonly property int dist: Math.abs(index - LyricsService.before)
                    font.pixelSize: {
                        if (dist === 0) return Appearance.font.pixelSize.normal * root.fontScale
                        if (dist === 1) return Appearance.font.pixelSize.small * root.fontScale
                        return Appearance.font.pixelSize.smaller * root.fontScale
                    }
                    opacity: {
                        if (dist === 0) return 1.0
                        if (dist === 1) return 0.6
                        if (dist === 2) return 0.35
                        return 0.15
                    }
                    color: dist === 0 ? root.activeColor : root.textColor
                    transform: Translate { id: lineSlide }
                    onTextChanged: {
                        if (root.animateTransitions) slideAnim.restart();
                    }
                    SequentialAnimation {
                        id: slideAnim
                        ScriptAction { script: lineSlide.y = 28 * root.fontScale }
                        NumberAnimation { target: lineSlide; property: "y"; to: 0; duration: 420; easing.type: Easing.OutBack }
                    }
                    Behavior on font.pixelSize {
                        enabled: root.animateTransitions
                        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
            }

        }
    }

    // Plain lyrics (no timestamps) scroll at an estimated pace: show a small badge
    Rectangle {
        visible: LyricsService.unsynced
        anchors.top: parent.top
        anchors.right: parent.right
        implicitWidth: badgeRow.implicitWidth + 12
        implicitHeight: badgeRow.implicitHeight + 4
        radius: height / 2
        color: ColorUtils.transparentize(root.indicatorColor, 0.55)
        RowLayout {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 3
            MaterialSymbol { text: "schedule"; iconSize: 12; color: root.textColor; opacity: 0.8 }
            StyledText {
                text: Translation.tr("Not synced")
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: root.textColor
                opacity: 0.8
            }
        }
    }
}
