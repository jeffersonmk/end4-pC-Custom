pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower

// Battery level of connected game controllers (Xbox, DualSense, ...) reported by UPower.
Item {
    id: root
    property color contentColor: Appearance.colors.colOnLayer1
    property bool contentColorOverridden: false
    signal styleEditorRequested()
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Appearance.barMaterialLook

    readonly property var controllers: PeripheralBattery.controllers
    readonly property bool hasControllers: controllers.length > 0

    visible: hasControllers
    implicitWidth: !hasControllers ? 0 : vertical ? Appearance.sizes.verticalBarWidth : layout.implicitWidth + 8
    implicitHeight: !hasControllers ? 0 : vertical ? layout.implicitHeight + 8 : Appearance.sizes.barHeight

    function brand(dev) {
        const m = (dev.model || "").toLowerCase()
        if (m.includes("xbox")) return "Xbox"
        if (m.includes("dualsense") || m.includes("dualshock") || m.includes("playstation") || m.includes("wireless controller")) return "PlayStation"
        return dev.model || Translation.tr("Controller")
    }

    GridLayout {
        id: layout
        anchors.centerIn: parent
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: root.vertical ? -1 : 1
        columns: root.vertical ? 1 : -1
        columnSpacing: 8
        rowSpacing: 6

        Repeater {
            model: ScriptModel {
                values: root.controllers
                objectProp: "nativePath"
            }
            delegate: Item {
                id: item
                required property var modelData
                readonly property real pct: modelData.percentage
                readonly property bool charging: modelData.state === UPowerDeviceState.Charging
                readonly property bool low: !charging && PeripheralBattery.isLow(modelData)
                readonly property color tint: low ? Appearance.m3colors.m3error : root.contentColor
                readonly property var btDevice: PeripheralBattery.bluetoothFor(modelData)

                // Stays true for a moment after the pointer leaves, so the
                // popup survives the gap between the bar and the card.
                property bool hoverHeld: false
                // The hover card gives way to the right-click menu.
                readonly property bool containsMouse: hoverHeld && !menuLoader.active
                readonly property bool rawHover: area.containsMouse || popup.hovered
                onRawHoverChanged: {
                    if (rawHover) { holdTimer.stop(); hoverHeld = true }
                    else holdTimer.restart()
                }
                Timer {
                    id: holdTimer
                    interval: 250
                    onTriggered: item.hoverHeld = false
                }

                Layout.alignment: Qt.AlignCenter
                implicitWidth: row.implicitWidth
                implicitHeight: row.implicitHeight

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressAndHold: mouse => {
                        if (mouse.button === Qt.RightButton) root.styleEditorRequested()
                    }
                    onClicked: mouse => {
                        if (mouse.button !== Qt.RightButton) return
                        if (menuLoader.active && menuLoader.item) menuLoader.item.close()
                        else menuLoader.active = true
                    }
                }

                GridLayout {
                    id: row
                    anchors.centerIn: parent
                    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                    columnSpacing: 3
                    rowSpacing: 0

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignCenter
                        text: item.charging ? "bolt" : "sports_esports"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.larger
                        color: item.tint
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignCenter
                        text: Math.round(item.pct * 100)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: item.tint
                    }
                }

                Loader {
                    id: menuLoader
                    active: false
                    sourceComponent: ControllerBatteryMenu {
                        device: item.modelData
                        btDevice: item.btDevice
                        brandName: root.brand(item.modelData)
                        anchor {
                            window: root.QsWindow.window
                            item: item
                            gravity: Config.options.bar.vertical
                                ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                                : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                            edges: Config.options.bar.vertical
                                ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
                                : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
                        }
                        onPopupClosed: menuLoader.active = false
                    }
                }

                ControllerBatteryPopup {
                    id: popup
                    hoverTarget: item
                    device: item.modelData
                    btDevice: item.btDevice
                    brandName: root.brand(item.modelData)
                }
            }
        }
    }
}
