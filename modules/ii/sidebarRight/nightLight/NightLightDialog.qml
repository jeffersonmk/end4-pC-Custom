import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

WindowDialog {
    id: root
    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    backgroundHeight: Math.min(980, (root.parent?.height ?? 1000) - 40)
    backgroundWidth: Math.min(390, (root.parent?.width ?? 400) - 16)

    WindowDialogTitle {
        text: Translation.tr("Eye protection")
    }
    WindowDialogSeparator {
        Layout.topMargin: -22
        Layout.leftMargin: 0
        Layout.rightMargin: 0
    }
    
    WindowDialogSectionHeader {
        text: Translation.tr("Night Light")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 16
        bgcolor: Appearance.colors.colSurfaceContainerHigh  
        ConfigSwitch {
            Layout.topMargin: -2
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "check"
            text: Translation.tr("Enable now")
            checked: Hyprsunset.temperatureActive
            onCheckedChanged: {
                Hyprsunset.toggleTemperature(checked)
            }
        }

        WindowDialogSlider {
            Layout.topMargin: -2    
            text: Translation.tr("")
            from: 6500
            to: 1200
            stopIndicatorValues: [5000, to]
            value: Config.options.light.night.colorTemperature
            onMoved: Config.options.light.night.colorTemperature = value
            tooltipContent: `${Math.round(value)}K`
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Schedule")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 12
        bgcolor: Appearance.colors.colSurfaceContainerHigh
        ConfigSwitch {
            Layout.topMargin: -2
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "night_sight_auto"
            text: Translation.tr("Automatic")
            checked: Config.options.light.night.automatic
            onCheckedChanged: {
                Config.options.light.night.automatic = checked;
            }
        }
        ConfigTimeRow {
            enabled: Config.options.light.night.automatic
            fieldHeight: 30
            Layout.leftMargin: 4
            Layout.rightMargin: 0
            text: Translation.tr("Turn on at")
            value: Config.options.light.night.from
            onEdited: newValue => { Config.options.light.night.from = newValue }
        }
        ConfigTimeRow {
            enabled: Config.options.light.night.automatic
            fieldHeight: 30
            Layout.leftMargin: 4
            Layout.rightMargin: 0
            text: Translation.tr("Turn off at")
            value: Config.options.light.night.to
            onEdited: newValue => { Config.options.light.night.to = newValue }
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: {
                const night = Config.options.light.night;
                if (!night.automatic) return Translation.tr("Automatic schedule is off: the night light only changes when you toggle it.");
                const from = Hyprsunset.timeToMinutes(night.from);
                const to = Hyprsunset.timeToMinutes(night.to);
                const length = ((to - from) % 1440 + 1440) % 1440;
                const hours = Math.floor(length / 60);
                const minutes = length % 60;
                const duration = minutes > 0 ? `${hours}h ${minutes}min` : `${hours}h`;
                return Translation.tr("On every day from %1 to %2 (%3).").arg(night.from).arg(night.to).arg(duration);
            }
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("When the PC starts")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 12
        bgcolor: Appearance.colors.colSurfaceContainerHigh
        ConfigSelectionArray {
            currentValue: Config.options.light.night.startup
            onSelected: newValue => { Config.options.light.night.startup = newValue }
            options: [
                { displayName: Translation.tr("Off"), icon: "light_off", value: "off" },
                { displayName: Translation.tr("On"), icon: "bedtime", value: "on" },
                { displayName: Translation.tr("Schedule"), icon: "night_sight_auto", value: "schedule" },
            ]
        }
        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: {
                switch (Config.options.light.night.startup) {
                    case "on": return Translation.tr("Starts on. The schedule takes over at its next on/off time.");
                    case "schedule": return Translation.tr("Starts on only if it's inside the scheduled hours.");
                    default: return Translation.tr("Starts off, even inside the scheduled hours. The schedule turns it on at the next start time.");
                }
            }
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Anti-flashbang (experimental)")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 16
        bgcolor: Appearance.colors.colSurfaceContainerHigh
        ConfigSwitch {
            Layout.topMargin: -2  
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "filter"
            text: Translation.tr("Content adjustment")
            checked: HyprlandAntiFlashbangShader.enabled
            onCheckedChanged: {
                if (checked) HyprlandAntiFlashbangShader.enable()
                else HyprlandAntiFlashbangShader.disable()
            }
            StyledToolTip {
                text: Translation.tr("<b>Dims screen content</b> as needed.<br><br>Pros: Immediately responsive<br>Cons: Expensive and can hurt color accuracy<br><br><i>Uses a Hyprland screen shader</i>")
            }
        }

        ConfigSwitch {
            Layout.topMargin: -2  
            iconSize: Appearance.font.pixelSize.larger
            buttonIcon: "light_mode"
            text: Translation.tr("Brightness adjustment")
            checked: Config.options.light.antiFlashbang.enable
            onCheckedChanged: {
                Config.options.light.antiFlashbang.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Adapts the <b>display (physical screen) brightness</b><br><br>Pros: Less expensive, retains colors<br>Cons: Not immediately responsive<br><br><i>Adjusts display brightness after each Hyprland IPC event</i>")
            }
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Brightness")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 16
        bgcolor: Appearance.colors.colSurfaceContainerHigh  

        WindowDialogSlider {
            Layout.topMargin: -2
            value: root.brightnessMonitor?.brightness ?? 0
            onMoved: root.brightnessMonitor?.setBrightness(value)
        }
    }

    WindowDialogSectionHeader {
        text: Translation.tr("Gamma")
        Layout.bottomMargin: -10
    }

    GroupedList {
        itemVerticalPadding: 16
        bgcolor: Appearance.colors.colSurfaceContainerHigh
        WindowDialogSlider {
            from: Hyprsunset.gammaLowerLimit / 100
            value: Hyprsunset.gamma / 100
            onMoved: Hyprsunset.setGamma(value * 100)
            tooltipContent: `${Math.round(value * 100)}%`
        }
    }
    
    WindowDialogButtonRow {
        Layout.fillWidth: true

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
        }
    }
}
