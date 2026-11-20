import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

// Hover card of a game controller: battery, state, connection and a power-off button.
StyledPopup {
    id: root

    required property var device          // UPower device
    property var btDevice: null           // matching Bluetooth device, null when wired
    property string brandName: ""
    readonly property bool hovered: popupHover.hovered

    readonly property real pct: device?.percentage ?? 0
    readonly property bool charging: device?.state === UPowerDeviceState.Charging
    readonly property bool full: device?.state === UPowerDeviceState.FullyCharged
    readonly property bool low: !!device && !charging && !full && PeripheralBattery.isLow(device)
    readonly property color accent: low ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
    readonly property string historyKey: device?.nativePath ?? ""
    readonly property int historyHours: 6
    property double now: Date.now()
    // Time from UPower when it knows it (Xbox pads); the DualSense reports
    // none, so fall back to the pace measured in the stored history.
    readonly property real reported: charging ? (device?.timeToFull ?? 0) : (device?.timeToEmpty ?? 0)
    readonly property real measured: { ControllerHistory.revision; return historyKey === "" ? 0 : ControllerHistory.estimate(historyKey, charging, pct) }
    readonly property real remaining: reported > 0 ? reported : measured
    readonly property var chartPoints: { ControllerHistory.revision; root.now; return historyKey === "" ? [] : ControllerHistory.chart(historyKey, historyHours * 3600000) }
    readonly property bool isDualSense: ControllerLight.isDualSense(device)

    function formatTime(seconds) {
        const h = Math.floor(seconds / 3600)
        const m = Math.floor((seconds % 3600) / 60)
        return h > 0 ? `${h}h ${m}m` : `${m}m`
    }

    Item {
        implicitWidth: 300
        implicitHeight: column.implicitHeight

        HoverHandler { id: popupHover }

        Timer {
            interval: 30000
            repeat: true
            running: root.shouldShow || root.closing
            triggeredOnStart: true
            onTriggered: root.now = Date.now()
        }

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                spacing: 8

                MaterialShapeWrappedMaterialSymbol {
                    shape: MaterialShape.Shape.Clover4Leaf
                    text: root.charging ? "bolt" : "sports_esports"
                    iconSize: Appearance.font.pixelSize.large
                    implicitSize: 36
                    color: root.low ? Appearance.m3colors.m3errorContainer : Appearance.colors.colPrimaryContainer
                    colSymbol: root.low ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -3

                    StyledText {
                        Layout.fillWidth: true
                        text: root.brandName
                        elide: Text.ElideRight
                        font {
                            weight: Font.Medium
                            pixelSize: Appearance.font.pixelSize.normal
                        }
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.charging ? Translation.tr("Charging")
                            : root.full ? Translation.tr("Fully charged")
                            : Translation.tr("On battery")
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.6
                    }
                }

                StyledText {
                    Layout.rightMargin: 8
                    text: `${Math.round(root.pct * 100)}%`
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.Bold
                    color: root.accent
                }
            }

            StyledProgressBar {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                Layout.rightMargin: 3
                valueBarWidth: 300
                valueBarHeight: 6
                value: root.pct
                highlightColor: root.accent
                trackColor: Appearance.colors.colSecondaryContainer
            }

            // Battery history graph (steps, because controllers report coarse levels)
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: historyColumn.implicitHeight + 20
                radius: Appearance.rounding.small
                color: Appearance.colors.colSurfaceContainerLow

                ColumnLayout {
                    id: historyColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                        rightMargin: 10
                    }
                    spacing: 4

                    Canvas {
                        id: chart
                        Layout.fillWidth: true
                        implicitHeight: 52
                        visible: root.chartPoints.length > 0
                        renderStrategy: Canvas.Cooperative

                        readonly property var points: root.chartPoints
                        readonly property color line: root.accent
                        readonly property real lowLevel: Config.options.battery.peripheralLow / 100
                        onPointsChanged: requestPaint()
                        onLineChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        Component.onCompleted: requestPaint()

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const pts = points
                            if (!pts || pts.length === 0) return
                            const pad = 3
                            const X = p => p.x * width
                            const Y = p => height - pad - p.y * (height - pad * 2)

                            // dashed "low battery" level
                            ctx.setLineDash([3, 4])
                            ctx.strokeStyle = Qt.rgba(line.r, line.g, line.b, 0.35)
                            ctx.lineWidth = 1
                            ctx.beginPath()
                            ctx.moveTo(0, Y({ y: lowLevel }))
                            ctx.lineTo(width, Y({ y: lowLevel }))
                            ctx.stroke()
                            ctx.setLineDash([])

                            // split into runs at session gaps, draw each as a step line
                            const runs = []
                            for (let i = 0; i < pts.length; i++) {
                                if (i === 0 || pts[i].gap) runs.push([])
                                runs[runs.length - 1].push(pts[i])
                            }
                            for (const run of runs) {
                                // a run of one reading (connected, then gone) gets a short stub
                                if (run.length === 1) run.push({ x: Math.min(1, run[0].x + 4 / width), y: run[0].y })
                                ctx.beginPath()
                                ctx.moveTo(X(run[0]), Y(run[0]))
                                for (let i = 1; i < run.length; i++) {
                                    ctx.lineTo(X(run[i]), Y(run[i - 1]))
                                    ctx.lineTo(X(run[i]), Y(run[i]))
                                }
                                ctx.lineWidth = 2
                                ctx.lineJoin = "round"
                                ctx.strokeStyle = line
                                ctx.stroke()
                                ctx.lineTo(X(run[run.length - 1]), height - pad)
                                ctx.lineTo(X(run[0]), height - pad)
                                ctx.closePath()
                                ctx.fillStyle = Qt.rgba(line.r, line.g, line.b, 0.16)
                                ctx.fill()
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.chartPoints.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Collecting battery history…")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSurfaceVariant
                        opacity: 0.6
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.chartPoints.length > 0
                        StyledText {
                            text: Translation.tr("%1 h ago").arg(root.historyHours)
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.6
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: Translation.tr("Now")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.6
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                Layout.rightMargin: 3
                spacing: 6

                StyledPopupValueRow {
                    Layout.fillWidth: true
                    visible: root.full || root.remaining > 0
                    icon: root.charging ? "bolt" : "schedule"
                    label: root.charging ? Translation.tr("Time to full") : Translation.tr("Time to empty")
                    value: root.full ? Translation.tr("Full")
                        : (root.reported > 0 ? "" : "~ ") + root.formatTime(root.remaining)
                }
                StyledPopupValueRow {
                    Layout.fillWidth: true
                    icon: root.btDevice ? "bluetooth_connected" : "usb"
                    label: Translation.tr("Connection")
                    value: root.btDevice ? "Bluetooth" : "USB"
                }
                StyledPopupValueRow {
                    Layout.fillWidth: true
                    visible: (root.device?.model ?? "") !== "" && root.device.model !== root.brandName
                    icon: "gamepad"
                    label: Translation.tr("Model")
                    value: root.device?.model ?? ""
                }
            }

            // DualSense light bar: leave it, follow the wallpaper theme, or turn it off
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                Layout.rightMargin: 3
                visible: root.isDualSense
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Item {
                        implicitWidth: Appearance.font.pixelSize.large
                        implicitHeight: Appearance.font.pixelSize.large
                        Layout.alignment: Qt.AlignVCenter
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: ControllerLight.mode === "default"
                            text: "lightbulb"
                            iconSize: Appearance.font.pixelSize.large
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            visible: ControllerLight.mode !== "default"
                            width: 14
                            height: 14
                            radius: 7
                            color: ControllerLight.shownColor
                            border.width: 1
                            border.color: Appearance.colors.colOutline
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Light bar")
                        color: Appearance.colors.colOnSurfaceVariant
                    }
                    Repeater {
                        model: [
                            { value: "default", label: Translation.tr("Normal") },
                            { value: "theme", label: Translation.tr("Theme") },
                            { value: "off", label: Translation.tr("Off") }
                        ]
                        delegate: RippleButton {
                            id: chip
                            required property var modelData
                            implicitHeight: 28
                            implicitWidth: chipLabel.implicitWidth + 20
                            topPadding: 0
                            bottomPadding: 0
                            buttonRadius: height / 2
                            toggled: ControllerLight.mode === modelData.value
                            colBackground: Appearance.colors.colLayer2Base
                            onClicked: ControllerLight.setMode(modelData.value)
                            contentItem: StyledText {
                                id: chipLabel
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                text: chip.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: ControllerLight.error !== ""
                    wrapMode: Text.WordWrap
                    text: ControllerLight.error === "no_permission"
                        ? Translation.tr("No permission to write to the controller (hidraw). Install the steam-devices udev rules.")
                        : Translation.tr("Could not change the light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3error
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: true
                visible: root.btDevice !== null
                materialIcon: "power_settings_new"
                mainText: Translation.tr("Turn off controller")
                colBackground: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.85)
                colBackgroundHover: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.7)
                colRipple: ColorUtils.transparentize(Appearance.m3colors.m3error, 0.5)
                onClicked: root.btDevice?.disconnect()
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 3
                visible: root.btDevice === null
                wrapMode: Text.WordWrap
                text: Translation.tr("Wired: unplug the cable to turn it off")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
                opacity: 0.6
            }
        }
    }
}
