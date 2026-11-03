import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Temperature (randomness) of the model: slider plus the usual presets
AiPopup {
    id: root
    title: Translation.tr("Temperature")
    icon: "device_thermostat"

    readonly property var presets: [
        { value: 0.2, label: Translation.tr("Precise"), icon: "target" },
        { value: 0.5, label: Translation.tr("Balanced"), icon: "balance" },
        { value: 1.0, label: Translation.tr("Creative"), icon: "palette" },
        { value: 1.5, label: Translation.tr("Wild"), icon: "casino" }
    ]

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: Translation.tr("Lower values give focused, repeatable answers; higher values give more varied ones. Applies to the next message.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        StyledText {
            text: Ai.temperature.toFixed(1)
            font.pixelSize: Appearance.font.pixelSize.title
            color: Appearance.colors.colPrimary
            Layout.preferredWidth: 44
        }
        StyledSlider {
            id: slider
            Layout.fillWidth: true
            from: 0
            to: 2
            stepSize: 0.1
            usePercentTooltip: false
            tooltipContent: value.toFixed(1)
            configuration: StyledSlider.Configuration.S
            value: Ai.temperature
            onMoved: Ai.setTemperature(Math.round(value * 10) / 10, false)
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.presets
            delegate: RippleButton {
                id: chip
                required property var modelData
                readonly property bool active: Math.abs(Ai.temperature - modelData.value) < 0.05
                implicitHeight: 32
                topPadding: 0
                bottomPadding: 0
                implicitWidth: chipRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.small
                toggled: active
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: Ai.setTemperature(modelData.value, false)
                contentItem: RowLayout {
                    id: chipRow
                    spacing: 5
                    MaterialSymbol {
                        text: chip.modelData.icon
                        iconSize: Appearance.font.pixelSize.larger
                        color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        text: chip.modelData.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }
}
