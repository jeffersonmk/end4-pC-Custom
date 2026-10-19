import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/*
 * MEGA bar widget: a simple icon showing the sync state.
 * Hover: MEGA details (space used, sync state, synced folders, transfers).
 * Left click: open MEGA (your MEGA webapp if you have one). Right click: refresh now.
 */
MouseArea {
    id: root
    property color contentColor: Appearance.colors.colOnLayer1
    property bool contentColorOverridden: false
    property bool vertical: Config.options.bar.vertical
    readonly property bool syncing: MegaCloud.status === "syncing"

    Component.onCompleted: MegaCloud.consumers++
    Component.onDestruction: MegaCloud.consumers--

    implicitWidth: vertical ? Appearance.sizes.verticalBarWidth : content.implicitWidth + 14
    implicitHeight: vertical ? content.implicitHeight + 8 : Appearance.sizes.barHeight

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) MegaCloud.refresh()
        else if (MegaCloud.loggedIn || !MegaCloud.installed) MegaCloud.openMega()
        else MegaCloud.openLoginTerminal()
    }

    Item {
        id: content
        anchors.centerIn: parent
        implicitWidth: icon.implicitWidth
        implicitHeight: icon.implicitHeight

        MaterialSymbol {
            id: icon
            anchors.centerIn: parent
            text: MegaCloud.icon
            iconSize: Appearance.font.pixelSize.larger
            color: MegaCloud.status === "error" ? Appearance.colors.colError : root.contentColor
            opacity: MegaCloud.loggedIn ? 1 : 0.55

            SequentialAnimation on opacity {
                running: root.syncing
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
    }

    MegaPopup {
        hoverTarget: root
    }
}
