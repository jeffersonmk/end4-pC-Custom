pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF

/**
 * Keyword search over Settings pages, sections and options.
 * Uses the same index as the launcher (SettingsSearchIndex).
 * Enter / click jumps to the result; Esc closes.
 */
Item {
    id: root

    property bool open: false
    signal resultChosen(var target)

    property string query: ""
    readonly property var results: query.trim().length > 0 ? SettingsSearchIndex.search(query, 60) : []
    property int selectedIndex: 0
    onResultsChanged: selectedIndex = 0

    function show() {
        root.query = "";
        searchField.text = "";
        root.open = true;
        searchField.forceActiveFocus();
    }

    function showWith(text) {
        root.show();
        searchField.text = text ?? "";
    }

    function hide() {
        root.open = false;
    }

    function choose(entry) {
        if (!entry) return;
        root.resultChosen({
            page: entry.pageId,
            label: entry.kind === "page" ? "" : entry.label,
            section: entry.section ?? "",
            subsection: entry.subsection ?? "",
        });
        root.hide();
    }

    function breadcrumb(entry) {
        if (entry.kind === "page") return Translation.tr("Page");
        const parts = [entry.pageName];
        if (entry.kind === "option") {
            if (entry.section) parts.push(entry.section);
            if (entry.subsection) parts.push(entry.subsection);
        }
        return parts.filter(part => part && part !== entry.label).join("  ›  ");
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    // Dim the settings behind; click outside to close
    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: CF.ColorUtils.transparentize(Appearance.colors.colLayer0Base, 0.25)
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
            onWheel: wheel => wheel.accepted = true
        }
    }

    Rectangle {
        id: card
        anchors {
            top: parent.top
            horizontalCenter: parent.horizontalCenter
            topMargin: 40
        }
        width: Math.min(parent.width - 60, 560)
        height: Math.min(parent.height - 80, column.implicitHeight + 20)
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: CF.ColorUtils.transparentize(Appearance.colors.colOutline, 0.8)
        scale: root.open ? 1 : 0.97
        Behavior on scale {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        // Swallow clicks inside the card
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: column
            anchors {
                fill: parent
                margins: 10
            }
            spacing: 8

            // Search field
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 6
                    }
                    spacing: 6
                    MaterialSymbol {
                        text: "search"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        background: null
                        placeholderText: Translation.tr("Search settings (e.g. blur, wallpaper, bar)")
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer1
                        selectedTextColor: Appearance.colors.colOnSecondaryContainer
                        selectionColor: Appearance.colors.colSecondaryContainer
                        renderType: Text.NativeRendering
                        font {
                            family: Appearance.font.family.main
                            pixelSize: Appearance.font.pixelSize.normal
                            variableAxes: Appearance.font.variableAxes.main
                        }
                        onTextChanged: root.query = text

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.hide();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                root.selectedIndex = Math.min(root.results.length - 1, root.selectedIndex + 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                                root.selectedIndex = Math.max(0, root.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.choose(root.results[root.selectedIndex]);
                                event.accepted = true;
                            }
                        }
                    }
                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        onClicked: {
                            if (searchField.text.length > 0) {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            } else {
                                root.hide();
                            }
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: 20
                            text: "close"
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            // Hint / no results
            StyledText {
                Layout.fillWidth: true
                Layout.margins: 8
                visible: root.results.length === 0
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                text: root.query.trim().length === 0
                    ? Translation.tr("Type a keyword to find a page, section or option")
                    : Translation.tr("Nothing found for \"%1\"").arg(root.query.trim())
            }

            // Results
            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                visible: root.results.length > 0
                clip: true
                spacing: 2
                model: root.results
                currentIndex: root.selectedIndex
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                ScrollBar.vertical: StyledScrollBar {}

                delegate: RippleButton {
                    id: resultItem
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.selectedIndex
                    width: list.width
                    implicitHeight: 52
                    buttonRadius: Appearance.rounding.normal
                    colBackground: selected ? Appearance.colors.colSecondaryContainer : "transparent"
                    colBackgroundHover: selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                    onHoveredChanged: if (hovered) root.selectedIndex = index
                    onClicked: root.choose(modelData)

                    contentItem: RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 12
                            rightMargin: 12
                        }
                        spacing: 12
                        Rectangle {
                            implicitWidth: 32
                            implicitHeight: 32
                            radius: width / 2
                            color: resultItem.selected ? Appearance.colors.colLayer1 : Appearance.colors.colSecondaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: resultItem.modelData.icon
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: resultItem.modelData.label
                                color: resultItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.breadcrumb(resultItem.modelData)
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        MaterialSymbol {
                            visible: resultItem.selected
                            text: "subdirectory_arrow_left"
                            iconSize: 18
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }
}
