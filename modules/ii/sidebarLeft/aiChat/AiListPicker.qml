import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Simple pick-from-a-list card (system prompts, saved chats).
 * items: [{ id, title, subtitle }]. With `inputPlaceholder` set it also shows a text field
 * with a button (used to name a chat before saving).
 */
AiPopup {
    id: root
    property var items: []
    property string currentId: ""
    property string emptyText: ""
    property string inputPlaceholder: ""
    property string inputActionText: ""
    property string inputActionIcon: "check"
    property alias inputText: nameField.text
    signal picked(string id)
    signal submitted(string text)

    onOpenChanged: if (open && inputPlaceholder.length > 0) {
        nameField.forceActiveFocus();
    }

    RowLayout {
        visible: root.inputPlaceholder.length > 0
        Layout.fillWidth: true
        spacing: 6
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            StyledTextInput {
                id: nameField
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                verticalAlignment: TextInput.AlignVCenter
                color: Appearance.colors.colOnLayer2
                onAccepted: if (text.trim().length > 0) root.submitted(text.trim())
                StyledText {
                    visible: nameField.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.inputPlaceholder
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
        RippleButtonWithIcon {
            enabled: nameField.text.trim().length > 0
            materialIcon: root.inputActionIcon
            mainText: root.inputActionText
            colBackground: Appearance.colors.colPrimaryContainer
            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
            mainContentComponent: Component {
                StyledText {
                    text: root.inputActionText
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            onClicked: root.submitted(nameField.text.trim())
        }
    }

    StyledText {
        visible: root.items.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.emptyText
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }

    ListView {
        id: list
        visible: root.items.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: contentHeight
        Layout.minimumHeight: Math.min(contentHeight, 60)
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}
        model: root.items
        delegate: RippleButton {
            id: row
            required property var modelData
            width: ListView.view.width
            implicitHeight: 46
            buttonRadius: Appearance.rounding.small
            toggled: modelData.id === root.currentId
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            onClicked: root.picked(modelData.id)
            contentItem: ColumnLayout {
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: row.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                }
                StyledText {
                    visible: text.length > 0
                    Layout.fillWidth: true
                    text: row.modelData.subtitle ?? ""
                    elide: Text.ElideMiddle
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
