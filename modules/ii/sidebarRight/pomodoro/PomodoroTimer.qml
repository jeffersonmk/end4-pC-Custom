import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    readonly property bool digital: Config.options.time.pomodoro.style === "digital"
    readonly property bool canEdit: !TimerService.pomodoroRunning
    readonly property bool canReset: (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration) || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    // Dial / digital switch
    RippleButton {
        id: styleButton
        z: 2
        anchors {
            top: parent.top
            right: parent.right
        }
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: Config.options.time.pomodoro.style = root.digital ? "dial" : "digital"
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: root.digital ? "nest_clock_farsight_analog" : "123"
            iconSize: 18
            color: Appearance.colors.colOnLayer2
        }
        StyledToolTip {
            text: root.digital ? Translation.tr("Dial view") : Translation.tr("Digital view")
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        Loader {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: root.digital
            sourceComponent: root.digital ? digitalComponent : dialComponent
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.digital ? 12 : 0
            spacing: 10

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.pomodoroRunning ? Translation.tr("Pause") : (TimerService.pomodoroSecondsLeft === TimerService.focusTime) ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.pomodoroRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.togglePomodoro()
                colBackground: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.pomodoroRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90
                onClicked: TimerService.resetPomodoro()
                enabled: root.canReset
                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }
    }

    // ── Original dial ──────────────────────────────────────────────
    Component {
        id: dialComponent
        Item {
            implicitWidth: 200
            implicitHeight: 200

            ClockPicker {
                anchors.fill: parent
                value: Math.round(TimerService.focusTime / 60)
                running: TimerService.pomodoroRunning
                onDragFinished: val => {
                    if (!TimerService.pomodoroRunning) {
                        Config.options.time.pomodoro.focus = val * 60;
                        TimerService.pomodoroSecondsLeft = val * 60;
                    }
                }
            }

            Rectangle {
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                anchors {
                    right: parent.right
                    bottom: parent.bottom
                }
                implicitWidth: 36
                implicitHeight: implicitWidth

                StyledText {
                    anchors.centerIn: parent
                    color: Appearance.colors.colOnLayer2
                    text: TimerService.pomodoroCycle + 1
                }
            }
        }
    }

    // ── Digital clock ──────────────────────────────────────────────
    Component {
        id: digitalComponent
        ColumnLayout {
            id: digitalView
            spacing: 8

            readonly property string phase: TimerService.pomodoroLongBreak ? "long" : TimerService.pomodoroBreak ? "break" : "focus"
            readonly property color phaseColor: phase === "focus" ? Appearance.colors.colPrimary : Appearance.colors.colTertiary

            // Phase + cycle
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 6

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: phaseRow.implicitWidth + 20
                    radius: Appearance.rounding.full
                    color: digitalView.phase === "focus" ? Appearance.colors.colPrimaryContainer : Appearance.colors.colTertiaryContainer

                    RowLayout {
                        id: phaseRow
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            text: digitalView.phase === "focus" ? "visibility" : digitalView.phase === "long" ? "park" : "coffee"
                            iconSize: 16
                            fill: 1
                            color: digitalView.phase === "focus" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnTertiaryContainer
                        }
                        StyledText {
                            text: digitalView.phase === "focus" ? Translation.tr("Focus") : digitalView.phase === "long" ? Translation.tr("Long break") : Translation.tr("Break")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: digitalView.phase === "focus" ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnTertiaryContainer
                        }
                    }
                }

                Rectangle {
                    implicitHeight: 26
                    implicitWidth: cycleText.implicitWidth + 18
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    StyledText {
                        id: cycleText
                        anchors.centerIn: parent
                        text: `${TimerService.pomodoroCycle + 1}/${TimerService.cyclesBeforeLongBreak}`
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.features: { "tnum": 1 }
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }

            // Big time
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    const t = Math.max(0, TimerService.pomodoroSecondsLeft);
                    const m = Math.floor(t / 60).toString().padStart(2, "0");
                    const s = Math.floor(t % 60).toString().padStart(2, "0");
                    return `${m}:${s}`;
                }
                font.pixelSize: 64
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                color: Appearance.m3colors.m3onSurface
            }

            // Progress of current phase
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 24
                Layout.rightMargin: 24
                implicitHeight: 6
                radius: 3
                color: Appearance.colors.colLayer2
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    radius: 3
                    color: digitalView.phaseColor
                    width: parent.width * Math.max(0, Math.min(1, 1 - TimerService.pomodoroSecondsLeft / Math.max(1, TimerService.pomodoroLapDuration)))
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }

            // Duration controls
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                spacing: 8

                DurationStepper {
                    icon: "visibility"
                    label: Translation.tr("Focus")
                    minutes: Math.round(TimerService.focusTime / 60)
                    onDecrease: TimerService.setFocusMinutes(minutes - 5)
                    onIncrease: TimerService.setFocusMinutes(minutes + 5)
                }
                DurationStepper {
                    icon: "coffee"
                    label: Translation.tr("Break")
                    minutes: Math.round(TimerService.breakTime / 60)
                    onDecrease: TimerService.setBreakMinutes(minutes - 1)
                    onIncrease: TimerService.setBreakMinutes(minutes + 1)
                }
            }
        }
    }

    component DurationStepper: Rectangle {
        id: stepper
        property string icon
        property string label
        property int minutes
        signal decrease()
        signal increase()

        implicitWidth: 150
        implicitHeight: 44
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer2
        opacity: root.canEdit ? 1 : 0.5

        RowLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            StepButton { symbol: "remove"; onClicked: stepper.decrease() }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -3
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: `${stepper.minutes} min`
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    font.features: { "tnum": 1 }
                    color: Appearance.colors.colOnLayer2
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 2
                    MaterialSymbol { text: stepper.icon; iconSize: 12; color: Appearance.colors.colSubtext }
                    StyledText {
                        text: stepper.label
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            StepButton { symbol: "add"; onClicked: stepper.increase() }
        }
    }

    component StepButton: RippleButton {
        id: stepButton
        property string symbol
        enabled: root.canEdit
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: stepButton.symbol
            iconSize: 18
            color: Appearance.colors.colOnLayer2
        }
    }
}
