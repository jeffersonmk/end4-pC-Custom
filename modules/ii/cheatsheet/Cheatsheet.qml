pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "CheatsheetData.js" as CheatsheetData

/**
 * Full-screen keybind cheatsheet: categories as cards in a masonry grid,
 * with a filter field at the bottom. Toggle with the "cheatsheetToggle"
 * global shortcut (Super + / by default) or `qs ipc call cheatsheet toggle`.
 */
Scope {
    id: root

    readonly property var categories: CheatsheetData.build([
        { tree: HyprlandKeybinds.defaultKeybinds, fallbackCategory: "Shell" },
        { tree: HyprlandKeybinds.userKeybinds, fallbackCategory: "Custom" },
    ])

    Loader {
        id: cheatsheetLoader
        active: GlobalStates.cheatsheetOpen

        sourceComponent: PanelWindow {
            id: panelWindow

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            function hide() {
                GlobalStates.cheatsheetOpen = false;
            }

            property string query: ""
            readonly property var filteredCategories: {
                const q = query.trim();
                return root.categories.map(category => ({
                    name: category.name,
                    icon: category.icon,
                    binds: category.binds.filter(bind => CheatsheetData.matches(bind, category.name, q)),
                })).filter(category => category.binds.length > 0);
            }
            readonly property int columnCount: Math.max(1, Math.min(4, Math.floor((width - 40) / 340)))
            readonly property var columns: CheatsheetData.distribute(filteredCategories, columnCount)

            // Dim backdrop, click to close
            Rectangle {
                anchors.fill: parent
                color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.12)
                opacity: content.opacity
                MouseArea {
                    anchors.fill: parent
                    onClicked: panelWindow.hide()
                }
            }

            Item {
                id: content
                anchors.fill: parent
                focus: true
                opacity: 0
                scale: 0.97
                Component.onCompleted: {
                    opacity = 1;
                    scale = 1;
                    filterField.forceActiveFocus();
                }
                Behavior on opacity {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                        event.accepted = true;
                    }
                }

                // Title pill
                Toolbar {
                    id: titleBar
                    anchors {
                        top: parent.top
                        horizontalCenter: parent.horizontalCenter
                        topMargin: 16
                    }
                    enableShadow: false
                    colBackground: Appearance.colors.colLayer1
                    RowLayout {
                        spacing: 8
                        Layout.leftMargin: 12
                        Layout.rightMargin: 14
                        MaterialSymbol {
                            text: "keyboard"
                            iconSize: 22
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            text: Translation.tr("Keybinds")
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.normal
                        }
                    }
                }

                // Close button
                RippleButton {
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 20
                        rightMargin: 20
                    }
                    implicitWidth: 40
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer1
                    onClicked: panelWindow.hide()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 22
                        text: "close"
                    }
                }

                // Cards
                StyledFlickable {
                    id: flickable
                    anchors {
                        top: titleBar.bottom
                        bottom: filterBar.top
                        left: parent.left
                        right: parent.right
                        topMargin: 14
                        bottomMargin: 14
                        leftMargin: 14
                        rightMargin: 14
                    }
                    clip: true
                    contentWidth: width
                    contentHeight: columnsRow.implicitHeight

                    // Swallow clicks so they don't close the panel
                    MouseArea {
                        width: flickable.width
                        height: Math.max(flickable.height, flickable.contentHeight)
                    }

                    Row {
                        id: columnsRow
                        width: flickable.width
                        spacing: 10
                        Repeater {
                            model: panelWindow.columns
                            delegate: Column {
                                id: column
                                required property var modelData
                                width: (columnsRow.width - columnsRow.spacing * (panelWindow.columnCount - 1)) / panelWindow.columnCount
                                spacing: 10
                                Repeater {
                                    model: column.modelData
                                    delegate: CategoryCard {
                                        required property var modelData
                                        width: column.width
                                        category: modelData
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: panelWindow.filteredCategories.length === 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 60
                        text: Translation.tr("No shortcuts match \"%1\"").arg(panelWindow.query)
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }

                // Filter
                Toolbar {
                    id: filterBar
                    anchors {
                        bottom: parent.bottom
                        horizontalCenter: parent.horizontalCenter
                        bottomMargin: 16
                    }
                    enableShadow: false
                    colBackground: Appearance.colors.colLayer1
                    MaterialSymbol {
                        Layout.leftMargin: 10
                        text: "filter_list"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer0
                    }
                    ToolbarTextField {
                        id: filterField
                        implicitWidth: 260
                        colBackground: "transparent"
                        placeholderText: Translation.tr("Filter shortcuts")
                        text: panelWindow.query
                        onTextChanged: panelWindow.query = text
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                if (text.length > 0) text = "";
                                else panelWindow.hide();
                                event.accepted = true;
                            }
                        }
                    }
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        enabled: panelWindow.query.length > 0
                        opacity: enabled ? 1 : 0.4
                        onClicked: {
                            filterField.text = "";
                            filterField.forceActiveFocus();
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: 20
                            text: "close"
                        }
                    }
                }
            }
        }
    }

    component CategoryCard: Rectangle {
        id: card
        property var category
        color: Appearance.colors.colLayer1
        radius: Appearance.rounding.large
        implicitHeight: cardColumn.implicitHeight + 28

        Column {
            id: cardColumn
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: 14
            }
            spacing: 10

            Row {
                spacing: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: width / 2
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.category.icon
                        iconSize: 18
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.category.name
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.family: Appearance.font.family.title
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: card.category.binds
                    delegate: Row {
                        id: bindRow
                        required property var modelData
                        width: cardColumn.width
                        spacing: 8
                        KeyCombo {
                            id: keysRow
                            anchors.verticalCenter: parent.verticalCenter
                            keys: bindRow.modelData.keys
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: bindRow.width - keysRow.width - bindRow.spacing
                            elide: Text.ElideRight
                            text: bindRow.modelData.description
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }
        }
    }

    component KeyCombo: Rectangle {
        id: combo
        property var keys: []
        implicitHeight: 24
        implicitWidth: comboRow.implicitWidth + 16
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer

        Row {
            id: comboRow
            anchors.centerIn: parent
            spacing: 5
            Repeater {
                model: combo.keys
                delegate: Item {
                    id: keyItem
                    required property string modelData
                    readonly property bool isSuper: modelData === "SUPER"
                    anchors.verticalCenter: parent?.verticalCenter
                    implicitWidth: isSuper ? superIcon.implicitWidth : keyText.implicitWidth
                    implicitHeight: 18
                    MaterialSymbol {
                        id: superIcon
                        visible: keyItem.isSuper
                        anchors.centerIn: parent
                        text: "keyboard_command_key"
                        iconSize: 15
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    StyledText {
                        id: keyText
                        visible: !keyItem.isSuper
                        anchors.centerIn: parent
                        text: keyItem.modelData
                        color: Appearance.colors.colOnSecondaryContainer
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Bold
                    }
                }
            }
        }
    }

    function toggle() {
        GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen;
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            GlobalStates.cheatsheetOpen = true;
        }
        function close(): void {
            GlobalStates.cheatsheetOpen = false;
        }
    }

    CompositorGlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"
        onPressed: root.toggle()
    }

    CompositorGlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"
        onPressed: GlobalStates.cheatsheetOpen = true
    }

    CompositorGlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"
        onPressed: GlobalStates.cheatsheetOpen = false
    }
}
