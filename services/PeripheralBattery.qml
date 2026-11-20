pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

Singleton {
    id: root

    readonly property var kinds: [UPowerDeviceType.Mouse, UPowerDeviceType.Keyboard, UPowerDeviceType.Headset,
        UPowerDeviceType.Headphones, UPowerDeviceType.GamingInput, UPowerDeviceType.Touchpad,
        UPowerDeviceType.Tablet, UPowerDeviceType.Phone]

    readonly property var devices: UPower.devices.values.filter(dev => dev.isPresent && root.kinds.includes(dev.type))

    readonly property var controllers: UPower.devices.values.filter(dev => dev.isPresent && dev.type === UPowerDeviceType.GamingInput && dev.percentage > 0)

    // Bluetooth device behind a UPower controller (null when wired): UPower's
    // native path usually carries the MAC, otherwise match by name.
    // Read here so the Bluetooth backend starts together with this singleton:
    // its device list is empty until the first read has been answered.
    readonly property var connectedBluetooth: Bluetooth.devices.values.filter(d => BluetoothStatus.isConnected(d))

    function bluetoothFor(dev) {
        if (!dev) return null
        const mac = ((dev.nativePath || "").match(/([0-9a-f]{2}[:_-]){5}[0-9a-f]{2}/i) ?? [""])[0].toLowerCase().replace(/[_-]/g, ":")
        const list = root.connectedBluetooth
        return list.find(d => mac !== "" && d.address.toLowerCase() === mac)
            ?? list.find(d => d.name === dev.model && Icons.getBluetoothDeviceMaterialSymbol(d.icon || "") === "gamepad")
            ?? null
    }

    function isDraining(dev) {
        return dev.state !== UPowerDeviceState.Charging && dev.state !== UPowerDeviceState.FullyCharged
    }

    function isLow(dev) {
        return dev.percentage > 0 && dev.percentage <= Config.options.battery.peripheralLow / 100 && root.isDraining(dev)
    }

    function isCritical(dev) {
        return dev.percentage > 0 && dev.percentage <= Config.options.battery.peripheralCritical / 100 && root.isDraining(dev)
    }

    readonly property var lowDevices: root.devices.filter(dev => root.isLow(dev))

    Instantiator {
        model: ScriptModel {
            values: root.devices
            objectProp: "nativePath"
        }
        delegate: Scope {
            id: tracker
            required property var modelData
            readonly property string name: (modelData.model || Translation.tr("Device")).replace(/ wireless controller$/i, "")
            readonly property bool low: root.isLow(modelData)
            readonly property bool critical: root.isCritical(modelData)
            readonly property bool isController: modelData.type === UPowerDeviceType.GamingInput
            readonly property bool full: modelData.state === UPowerDeviceState.FullyCharged
                || (modelData.state === UPowerDeviceState.Charging && modelData.percentage >= 0.99)

            // Level history for the controller card (graph and time estimate).
            readonly property string historyKey: modelData.nativePath
            readonly property real pct: modelData.percentage
            readonly property string stateKey: modelData.state === UPowerDeviceState.Charging ? "c"
                : modelData.state === UPowerDeviceState.FullyCharged ? "f" : "d"
            // Readings change while the delegate is still being set up; only the
            // first one after that counts as the start of a session.
            property bool tracking: false
            onPctChanged: if (tracking && isController && pct > 0) ControllerHistory.record(historyKey, pct, stateKey, false)
            onStateKeyChanged: if (tracking && isController && pct > 0) ControllerHistory.record(historyKey, pct, stateKey, false)
            Component.onCompleted: {
                if (isController && pct > 0) ControllerHistory.record(historyKey, pct, stateKey, true)
                tracking = true
            }

            // `notify-send -A` prints the chosen action id and exits when the
            // notification closes, so the "Turn off controller" button works
            // from the notification itself. `timeout` caps a notification that
            // is never closed.
            Component {
                id: noticeComp
                Process {
                    id: notice
                    stdout: SplitParser {
                        onRead: line => {
                            if (line.trim() === "off") tracker.turnOff()
                        }
                    }
                    onExited: notice.destroy()
                }
            }

            function turnOff() {
                root.bluetoothFor(modelData)?.disconnect()
            }

            function notify(title, body, urgency) {
                const command = ["timeout", "900", "notify-send", title, body, "-a", "Shell", "--hint=int:transient:1"]
                if (urgency) command.push("-u", urgency)
                if (isController && root.bluetoothFor(modelData))
                    command.push("-A", "off=" + Translation.tr("Turn off controller"))
                noticeComp.createObject(tracker, { command: command, running: true })
            }

            onLowChanged: {
                if (!low || critical || !Config.options.battery.peripheralNotify) return;
                notify(Translation.tr("%1 battery low").arg(tracker.name),
                    Translation.tr("%1% remaining").arg(Math.round(modelData.percentage * 100)), "")
            }

            onCriticalChanged: {
                if (!critical || !Config.options.battery.peripheralNotify) return;
                notify(Translation.tr("%1 battery critically low").arg(tracker.name),
                    Translation.tr("%1% remaining, please charge it").arg(Math.round(modelData.percentage * 100)), "critical")
            }

            onFullChanged: {
                if (!full || !isController || !Config.options.battery.peripheralFullNotify) return;
                notify(Translation.tr("%1 fully charged").arg(tracker.name),
                    Translation.tr("You can unplug it"), "")
            }
        }
    }
}
