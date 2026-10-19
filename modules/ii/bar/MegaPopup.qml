import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// MEGA details for the bar widget: space used, sync state, synced folders and transfers.
StyledPopup {
    id: root

    readonly property bool problem: MegaCloud.status === "error"
    readonly property color usageColor: MegaCloud.usedFraction > 0.9 ? Appearance.colors.colError
        : MegaCloud.usedFraction > 0.75 ? Appearance.m3colors.m3tertiary
        : Appearance.colors.colPrimary

    component InfoRow: RowLayout {
        id: infoRow
        property string icon
        property string label
        property string value
        property color valueColor: Appearance.colors.colOnSurfaceVariant
        Layout.fillWidth: true
        spacing: 8
        MaterialSymbol {
            text: infoRow.icon
            iconSize: Appearance.font.pixelSize.large
            color: infoRow.valueColor
        }
        StyledText {
            Layout.fillWidth: true
            text: infoRow.label
            elide: Text.ElideMiddle
            color: Appearance.colors.colOnSurfaceVariant
        }
        StyledText {
            Layout.leftMargin: 8
            text: infoRow.value
            color: infoRow.valueColor
            opacity: 0.75
        }
    }

    // Fixed width: the popup centers its content without sizing it, so a bare layout would shrink
    Item {
        implicitWidth: 320
        implicitHeight: column.implicitHeight

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                spacing: 10
                MaterialShapeWrappedMaterialSymbol {
                    shape: MaterialShape.Shape.Circle
                    text: MegaCloud.icon
                    iconSize: Appearance.font.pixelSize.large
                    implicitSize: 38
                    color: root.problem ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                    colSymbol: root.problem ? Appearance.colors.colOnErrorContainer : Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: "MEGA"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: MegaCloud.stateText
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.problem ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                        opacity: root.problem ? 1 : 0.65
                    }
                }
            }

            // Space used
            Rectangle {
                Layout.fillWidth: true
                visible: MegaCloud.loggedIn
                implicitHeight: space.implicitHeight + 28
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerLow

                ColumnLayout {
                    id: space
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Cloud space")
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.65
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        StyledText {
                            Layout.alignment: Qt.AlignBaseline
                            text: MegaCloud.formatSize(MegaCloud.used)
                            color: Appearance.colors.colOnSurfaceVariant
                            font.pixelSize: Appearance.font.pixelSize.huge
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignBaseline
                            Layout.fillWidth: true
                            text: Translation.tr("of %1").arg(MegaCloud.formatSize(MegaCloud.total))
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.65
                        }
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        valueBarWidth: 292
                        valueBarHeight: 6
                        value: MegaCloud.usedFraction
                        highlightColor: root.usageColor
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            text: Translation.tr("%1% used").arg(Math.round(MegaCloud.usedFraction * 1000) / 10)
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.65
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: Translation.tr("%1 free").arg(MegaCloud.formatSize(Math.max(0, MegaCloud.total - MegaCloud.used)))
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.65
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }

            // Synced folders and transfers
            Rectangle {
                Layout.fillWidth: true
                visible: MegaCloud.loggedIn
                implicitHeight: activity.implicitHeight + 24
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerLow

                ColumnLayout {
                    id: activity
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                    spacing: 10

                    InfoRow {
                        visible: MegaCloud.syncs.length === 0
                        icon: "folder_off"
                        label: Translation.tr("Synced folders")
                        value: Translation.tr("None")
                    }
                    Repeater {
                        model: MegaCloud.syncs
                        delegate: InfoRow {
                            required property var modelData
                            icon: modelData.error !== "" ? "sync_problem" : modelData.status === "Synced" ? "cloud_done" : "cloud_sync"
                            label: modelData.local.replace(/^\/home\/[^/]+/, "~")
                            value: modelData.error !== "" ? modelData.error : modelData.run === "Running" ? modelData.status : modelData.run
                            valueColor: modelData.error !== "" ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
                        }
                    }
                    InfoRow {
                        icon: "swap_vert"
                        label: Translation.tr("Transfers")
                        value: MegaCloud.uploads > 0 || MegaCloud.downloads > 0
                            ? `↑ ${MegaCloud.uploads}   ↓ ${MegaCloud.downloads}`
                            : Translation.tr("None")
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                visible: !MegaCloud.loggedIn
                wrapMode: Text.WordWrap
                text: MegaCloud.installed
                    ? Translation.tr("Click to log in: run mega-login your@email in the terminal that opens")
                    : Translation.tr("Install MEGAcmd (paru -S megacmd) to use this widget")
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            StyledText {
                Layout.fillWidth: true
                visible: MegaCloud.loggedIn
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Click: open MEGA · Right click: refresh")
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.5
                font.pixelSize: Appearance.font.pixelSize.smallest
            }
        }
    }
}
