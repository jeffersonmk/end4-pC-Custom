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
 * Cheat sheet (window or full screen) with two tabs:
 *  - Keybinds: categories as cards in a masonry grid, filter field at the bottom
 *  - System: PC specs and live usage/temperatures (SystemInfoPage.qml)
 * Toggle with the "cheatsheetToggle" global shortcut (Super + / by default) or
 * `qs ipc call cheatsheet toggle|keybinds|system`. Ctrl+Tab switches tabs.
 */
Scope {
    id: root

    // Appearance options (Settings > Interface > Cheat sheet)
    readonly property var displayOptions: ({
        superKey: Config.options.cheatsheet.superKey,
        useMacSymbol: Config.options.cheatsheet.useMacSymbol,
        useFnSymbol: Config.options.cheatsheet.useFnSymbol,
        useMouseSymbol: Config.options.cheatsheet.useMouseSymbol,
    })
    readonly property bool splitButtons: Config.options.cheatsheet.splitButtons
    readonly property bool fullscreen: Config.options.cheatsheet.displayMode === "fullscreen"
    // 0 = Keybinds, 1 = System. Kept between openings.
    property int currentTab: 0
    readonly property var tabs: [
        { "name": Translation.tr("Keybinds"), "icon": "keyboard" },
        { "name": Translation.tr("System"), "icon": "monitor_heart" }
    ]
    readonly property int keyFontSize: Config.options.cheatsheet.fontSize.key
    readonly property int commentFontSize: Config.options.cheatsheet.fontSize.comment

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
            readonly property int columnCount: Math.max(1, Math.min(4, Math.floor((content.width - 28) / 340)))
            readonly property var columns: CheatsheetData.distribute(filteredCategories, columnCount)

            // Light dim behind the window (kept under Hyprland's ignore_alpha so
            // only the window itself gets blurred); click outside to close
            Rectangle {
                anchors.fill: parent
                // Fullscreen: nearly opaque so it reads as its own screen (alpha stays above
                // ignore_alpha, so Hyprland blurs it). Window: light dim, desktop stays visible.
                color: ColorUtils.transparentize(Appearance.colors.colLayer0Base, root.fullscreen ? 0.12 : 0.65)
                opacity: content.opacity
                MouseArea {
                    anchors.fill: parent
                    onClicked: panelWindow.hide()
                }
            }

            StyledRectangularShadow {
                visible: !root.fullscreen
                target: content
                opacity: content.opacity
            }

            // Rounded window
            Rectangle {
                id: content
                anchors.centerIn: parent
                width: root.fullscreen ? parent.width : Math.min(parent.width - 120, 1560)
                // Height follows the full (unfiltered) list so the window doesn't jump while filtering
                property real naturalHeight: 0
                readonly property real wantedHeight: 16 + titleBar.implicitHeight + 14 + columnsRow.implicitHeight + 14 + filterBar.implicitHeight + 16
                onWantedHeightChanged: if (panelWindow.query.length === 0) naturalHeight = wantedHeight
                readonly property real systemHeight: 16 + titleBar.implicitHeight + 14 + systemPage.implicitHeight + 20
                height: root.fullscreen ? parent.height : Math.min(parent.height - 100, Math.max(root.currentTab === 1 ? systemHeight : naturalHeight, 360))
                Behavior on height {
                    enabled: !root.fullscreen
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
                radius: root.fullscreen ? 0 : Appearance.rounding.windowRounding
                color: root.fullscreen ? "transparent" : Appearance.colors.colLayer0
                border.width: root.fullscreen ? 0 : 1
                border.color: Appearance.colors.colLayer0Border
                clip: true
                focus: true

                // Swallow clicks inside the window so they don't close it
                MouseArea {
                    anchors.fill: parent
                }
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

                function switchTab(delta) {
                    root.currentTab = (root.currentTab + delta + root.tabs.length) % root.tabs.length;
                    if (root.currentTab === 0) filterField.forceActiveFocus();
                    else content.forceActiveFocus();
                }
                // Ctrl+Tab / Ctrl+PgUp/PgDn switch tabs (also while typing in the filter)
                function handleTabKeys(event) {
                    if (!(event.modifiers & Qt.ControlModifier)) return false;
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown) { switchTab(1); return true; }
                    if (event.key === Qt.Key_Backtab || event.key === Qt.Key_PageUp) { switchTab(-1); return true; }
                    return false;
                }

                Keys.onPressed: event => {
                    if (content.handleTabKeys(event)) {
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
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
                    ToolbarTabBar {
                        id: tabBar
                        tabButtonList: root.tabs
                        // Ignore index changes emitted while the bar is being built
                        property bool ready: false
                        Component.onCompleted: {
                            setCurrentIndex(root.currentTab);
                            ready = true;
                        }
                        Connections {
                            target: root
                            function onCurrentTabChanged() {
                                if (tabBar.currentIndex !== root.currentTab) tabBar.setCurrentIndex(root.currentTab);
                            }
                        }
                        onCurrentIndexChanged: if (ready && root.currentTab !== currentIndex) {
                            root.currentTab = currentIndex;
                            if (currentIndex === 0) filterField.forceActiveFocus();
                            else content.forceActiveFocus();
                        }
                    }
                }

                // Close button
                RippleButton {
                    anchors {
                        top: parent.top
                        right: parent.right
                        topMargin: 16
                        rightMargin: 16
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
                    visible: root.currentTab === 0
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

                // System info
                StyledFlickable {
                    id: systemFlickable
                    visible: root.currentTab === 1
                    anchors {
                        top: titleBar.bottom
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                        topMargin: 14
                        bottomMargin: 14
                        leftMargin: 14
                        rightMargin: 14
                    }
                    clip: true
                    contentWidth: width
                    contentHeight: systemPage.implicitHeight
                    SystemInfoPage {
                        id: systemPage
                        width: systemFlickable.width
                        // Only poll sensors while the tab is on screen
                        active: root.currentTab === 1
                    }
                }

                // Filter
                Toolbar {
                    id: filterBar
                    visible: root.currentTab === 0
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
                            if (content.handleTabKeys(event)) {
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
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
                            keys: CheatsheetData.displayParts(bindRow.modelData, root.displayOptions)
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: bindRow.width - keysRow.width - bindRow.spacing
                            elide: Text.ElideRight
                            text: bindRow.modelData.description
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: root.commentFontSize
                        }
                    }
                }
            }
        }
    }

    // Keycaps for one shortcut: a single pill, or one pill per key with "+"
    // between them when "Split buttons" is on.
    component KeyCombo: Row {
        id: combo
        property var keys: []
        spacing: root.splitButtons ? 3 : 0

        Repeater {
            model: root.splitButtons ? combo.keys.map(k => [k]) : [combo.keys]
            delegate: Row {
                id: group
                required property var modelData
                required property int index
                anchors.verticalCenter: parent?.verticalCenter
                spacing: 3

                StyledText {
                    visible: group.index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: root.keyFontSize
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: Math.max(24, root.keyFontSize + 12)
                    implicitWidth: pillRow.implicitWidth + 16
                    radius: root.splitButtons ? Appearance.rounding.verysmall : Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer

                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 5
                        Repeater {
                            model: group.modelData
                            delegate: Item {
                                id: keyItem
                                required property string modelData
                                readonly property bool isSuper: modelData === "SUPER"
                                anchors.verticalCenter: parent?.verticalCenter
                                implicitWidth: isSuper ? superIcon.implicitWidth : keyText.implicitWidth
                                implicitHeight: Math.max(18, root.keyFontSize + 6)
                                MaterialSymbol {
                                    id: superIcon
                                    visible: keyItem.isSuper
                                    anchors.centerIn: parent
                                    text: "keyboard_command_key"
                                    iconSize: root.keyFontSize + 3
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    id: keyText
                                    visible: !keyItem.isSuper
                                    anchors.centerIn: parent
                                    text: keyItem.modelData
                                    color: Appearance.colors.colOnSecondaryContainer
                                    // Nerd Font so symbols (super key, macOS mods, F-keys, mouse) render
                                    font.family: Appearance.font.family.iconNerd
                                    font.pixelSize: root.keyFontSize
                                    font.weight: Font.Bold
                                }
                            }
                        }
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
        function keybinds(): void {
            root.currentTab = 0;
            GlobalStates.cheatsheetOpen = true;
        }
        function system(): void {
            root.currentTab = 1;
            GlobalStates.cheatsheetOpen = true;
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

    // Opens straight on the System tab (hardware, usage, temperatures).
    // Closes it if it's already showing that tab.
    CompositorGlobalShortcut {
        name: "systemInfoToggle"
        description: "Toggles the system info (hardware/temperatures) tab"
        onPressed: {
            if (GlobalStates.cheatsheetOpen && root.currentTab === 1) {
                GlobalStates.cheatsheetOpen = false;
            } else {
                root.currentTab = 1;
                GlobalStates.cheatsheetOpen = true;
            }
        }
    }
}
