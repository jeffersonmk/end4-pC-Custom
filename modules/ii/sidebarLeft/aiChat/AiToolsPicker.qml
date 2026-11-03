import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Functions menu: master switch plus one switch per function the model may call, with what
 * each one can do. Warns when the current model can't use functions at all.
 */
AiPopup {
    id: root
    title: Translation.tr("Functions")
    icon: "service_toolbox"

    readonly property bool masterOn: Ai.currentTool === "functions"
    readonly property var functionRows: [
        {
            key: "readConfig",
            icon: "visibility",
            title: Translation.tr("Read shell settings"),
            description: Translation.tr("Lets the model look at your shell configuration. Read only."),
            risk: "safe"
        },
        {
            key: "editConfig",
            icon: "tune",
            title: Translation.tr("Change shell settings"),
            description: Translation.tr("Lets the model change a setting. It is applied right away, without asking."),
            risk: "careful",
            needs: "readConfig"
        },
        {
            key: "runCommands",
            icon: "terminal",
            title: Translation.tr("Run commands"),
            description: Translation.tr("Lets the model propose terminal commands. Each one waits for your approval."),
            risk: "asks"
        }
    ]

    component SwitchRow: Rectangle {
        id: row
        property string symbol
        property string title
        property string description
        property string badge
        property color badgeColor: Appearance.colors.colSecondaryContainer
        property color badgeTextColor: Appearance.colors.colOnSecondaryContainer
        property bool checked: false
        property bool rowEnabled: true
        signal toggled()

        Layout.fillWidth: true
        implicitHeight: rowLayout.implicitHeight + 16
        radius: Appearance.rounding.small
        color: rowMouse.containsMouse && row.rowEnabled ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer2
        opacity: row.rowEnabled ? 1 : 0.45

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.rowEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: row.toggled()
        }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.margins: 8
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: row.symbol
                iconSize: Appearance.font.pixelSize.huge
                color: row.checked && row.rowEnabled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: row.title
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }
                    Rectangle {
                        visible: row.badge.length > 0
                        implicitHeight: 18
                        implicitWidth: badgeText.implicitWidth + 12
                        radius: Appearance.rounding.full
                        color: row.badgeColor
                        StyledText {
                            id: badgeText
                            anchors.centerIn: parent
                            text: row.badge
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: row.badgeTextColor
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: row.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            StyledSwitch {
                Layout.alignment: Qt.AlignTop
                checked: row.checked
                enabled: false // the row handles the click
                opacity: 1
            }
        }
    }

    // Master switch
    SwitchRow {
        symbol: "power_settings_new"
        title: Translation.tr("Allow functions")
        description: Translation.tr("Functions let the model act on your PC instead of only answering. Off = plain chat.")
        checked: root.masterOn
        onToggled: Ai.setTool(root.masterOn ? "none" : "functions")
    }

    // The model can't use them
    Rectangle {
        visible: !Ai.currentModelSupportsTools
        Layout.fillWidth: true
        implicitHeight: warnRow.implicitHeight + 16
        radius: Appearance.rounding.small
        color: Appearance.colors.colErrorContainer
        RowLayout {
            id: warnRow
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8
            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: "warning"
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.m3colors.m3onErrorContainer
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.m3colors.m3onErrorContainer
                text: Translation.tr("%1 does not support functions, so none are sent to it. Pick a model with the Tools badge (for example Qwen3 or Llama 3.2) to use them.").arg(Ai.getModel().name)
            }
        }
    }

    Repeater {
        model: root.functionRows
        delegate: SwitchRow {
            id: fnRow
            required property var modelData
            readonly property bool needsMet: !modelData.needs || (Config.options.ai.functions[modelData.needs] ?? true)
            Layout.fillWidth: true
            symbol: modelData.icon
            title: modelData.title
            description: needsMet ? modelData.description : Translation.tr("Turn on “Read shell settings” first: the model has to read a setting before it changes it.")
            rowEnabled: root.masterOn && needsMet
            checked: (Config.options.ai.functions[modelData.key] ?? true) && needsMet
            badge: modelData.risk === "safe" ? Translation.tr("Safe")
                : modelData.risk === "asks" ? Translation.tr("Asks first")
                : Translation.tr("Applies instantly")
            badgeColor: modelData.risk === "careful" ? Appearance.colors.colTertiaryContainer : Appearance.colors.colSecondaryContainer
            badgeTextColor: modelData.risk === "careful" ? Appearance.m3colors.m3onTertiaryContainer : Appearance.colors.colOnSecondaryContainer
            onToggled: Config.options.ai.functions[modelData.key] = !(Config.options.ai.functions[modelData.key] ?? true)
        }
    }
}
