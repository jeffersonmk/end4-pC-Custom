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
    property bool isMaterial: Config.options.bar.cornerStyle === 3 || Config.options.bar.cornerStyle === 4

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
            delegate: MouseArea {
                id: item
                required property var modelData
                readonly property real pct: modelData.percentage
                readonly property bool charging: modelData.state === UPowerDeviceState.Charging
                readonly property bool low: !charging && PeripheralBattery.isLow(modelData)
                readonly property color tint: low ? Appearance.m3colors.m3error : root.contentColor

                Layout.alignment: Qt.AlignCenter
                implicitWidth: row.implicitWidth
                implicitHeight: row.implicitHeight
                hoverEnabled: true

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

                StyledToolTip {
                    text: `${root.brand(item.modelData)} • ${Math.round(item.pct * 100)}%` + (item.charging ? " ⚡" : "")
                }
            }
        }
    }
}
