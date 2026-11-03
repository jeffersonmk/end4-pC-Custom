import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * Card that opens inside the Intelligence panel (dimmed backdrop, click outside or Esc to close).
 * Content goes in as children; extra header buttons through `headerActions`.
 */
Item {
    id: root
    property bool open: false
    property string title: ""
    property string icon: ""
    property bool anchorBottom: false
    property real topReserve: 52
    property real bottomReserve: 6
    readonly property real maxCardHeight: Math.max(120, root.height - topReserve - bottomReserve)
    property alias headerActions: headerActionsRow.data
    default property alias content: contentArea.data
    signal closed()

    function show() { root.open = true }
    function close() {
        if (!root.open) return;
        root.open = false;
        root.closed();
    }

    z: 20
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.15)
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: root.close()
    }

    StyledRectangularShadow {
        target: card
    }
    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: root.anchorBottom ? undefined : parent.top
        anchors.topMargin: root.topReserve
        anchors.bottom: root.anchorBottom ? parent.bottom : undefined
        anchors.bottomMargin: root.bottomReserve
        width: parent.width - 12
        height: Math.min(cardColumn.implicitHeight + 20, root.maxCardHeight)
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer3Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        clip: true

        // Keep clicks inside the card from reaching the backdrop
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    visible: root.icon.length > 0
                    text: root.icon
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colPrimary
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer3
                }
                RowLayout {
                    id: headerActionsRow
                    spacing: 2
                }
                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    onClicked: root.close()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledToolTip { text: Translation.tr("Close") }
                }
            }

            ColumnLayout {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8
            }
        }
    }
}
