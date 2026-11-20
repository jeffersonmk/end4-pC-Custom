pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell

// Right-click menu of the controller battery widget.
PopupWindow {
    id: root

    required property var device           // UPower device
    property var btDevice: null            // Bluetooth device, null when wired
    property string brandName: ""
    signal popupClosed()

    readonly property real cardWidth: 290
    readonly property real cardPadding: 8
    property bool closing: false
    readonly property bool barVertical: Config.options.bar.vertical
    readonly property string barEdge: {
        if (!barVertical) return Config.options.bar.bottom ? "bottom" : "top"
        return Config.options.bar.bottom ? "right" : "left"
    }
    readonly property real bounceRoom: 24

    color: "transparent"
    implicitWidth: root.cardWidth + Appearance.sizes.elevationMargin * 2 + (barVertical ? bounceRoom : 0)
    implicitHeight: card.implicitHeight + Appearance.sizes.elevationMargin * 2 + (barVertical ? 0 : bounceRoom)

    function open() {
        root.visible = true
        closeAnim.stop()
        openAnim.restart()
    }

    function close() {
        if (root.closing) return
        root.closing = true
        openAnim.stop()
        closeAnim.restart()
    }

    Component.onCompleted: {
        GlobalFocusGrab.addDismissable(root)
        root.open()
    }
    Component.onDestruction: GlobalFocusGrab.removeDismissable(root)

    Connections {
        target: GlobalFocusGrab
        function onDismissed() { root.close() }
    }

    ParallelAnimation {
        id: openAnim
        NumberAnimation {
            target: cardScale
            property: root.barVertical ? "xScale" : "yScale"
            to: 1
            duration: 400
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: cardScale
            property: root.barVertical ? "yScale" : "xScale"
            to: 1
            duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
        NumberAnimation {
            target: card
            property: "opacity"
            to: 1
            duration: Appearance.animationCurves.expressiveEffectsDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        NumberAnimation {
            target: content
            property: "opacity"
            to: 1
            duration: Appearance.animationCurves.expressiveEffectsDuration
        }
    }

    ParallelAnimation {
        id: closeAnim
        onFinished: {
            root.visible = false
            root.popupClosed()
        }
        NumberAnimation {
            target: cardScale
            property: root.barVertical ? "xScale" : "yScale"
            to: 0.4
            duration: 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        NumberAnimation {
            target: card
            property: "opacity"
            to: 0
            duration: 180
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
    }

    component MenuItem: RippleButton {
        id: item
        property string symbol
        property string label
        property color tint: Appearance.colors.colOnSurface
        Layout.fillWidth: true
        implicitHeight: 40
        buttonRadius: Appearance.rounding.small
        colBackground: "transparent"
        contentItem: RowLayout {
            spacing: 10
            MaterialSymbol {
                Layout.leftMargin: 8
                Layout.alignment: Qt.AlignVCenter
                text: item.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: item.tint
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: item.label
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: item.tint
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()

        StyledRectangularShadow {
            target: card
            opacity: card.opacity
        }

        Rectangle {
            id: card
            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + (root.barEdge === "right" ? root.bounceRoom : 0)
                rightMargin: Appearance.sizes.elevationMargin + (root.barEdge === "left" ? root.bounceRoom : 0)
                topMargin: Appearance.sizes.elevationMargin + (root.barEdge === "bottom" ? root.bounceRoom : 0)
                bottomMargin: Appearance.sizes.elevationMargin + (root.barEdge === "top" ? root.bounceRoom : 0)
            }
            implicitHeight: content.implicitHeight + root.cardPadding * 2
            radius: Appearance.rounding.large
            color: Appearance.colors.colUiPopupBackground
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            opacity: 0
            transform: Scale {
                id: cardScale
                origin.x: root.barEdge === "left" ? 0 : root.barEdge === "right" ? card.width : card.width / 2
                origin.y: root.barEdge === "top" ? 0 : root.barEdge === "bottom" ? card.height : card.height / 2
                xScale: root.barVertical ? 0.4 : 0.8
                yScale: root.barVertical ? 0.8 : 0.4
            }

            ColumnLayout {
                id: content
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: root.cardPadding
                }
                spacing: 2
                opacity: 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 10
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    text: `${root.brandName} · ${Math.round((root.device?.percentage ?? 0) * 100)}%`
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.7
                }

                MenuItem {
                    visible: root.btDevice !== null
                    symbol: "power_settings_new"
                    label: Translation.tr("Turn off controller")
                    tint: Appearance.m3colors.m3error
                    onClicked: {
                        root.btDevice?.disconnect()
                        root.close()
                    }
                }
                MenuItem {
                    symbol: "bluetooth"
                    label: Translation.tr("Bluetooth settings")
                    onClicked: {
                        GlobalStates.requestBluetoothDialog()
                        root.close()
                    }
                }
                MenuItem {
                    symbol: "sports_esports"
                    label: Translation.tr("Gamepad settings")
                    onClicked: {
                        GlobalStates.openSettingsAt("services", "", Translation.tr("Gamepad"), "")
                        root.close()
                    }
                }
                MenuItem {
                    symbol: "notifications"
                    label: Translation.tr("Battery notifications")
                    onClicked: {
                        GlobalStates.openSettingsAt("general", "", Translation.tr("Device batteries"), "")
                        root.close()
                    }
                }
            }
        }
    }
}
