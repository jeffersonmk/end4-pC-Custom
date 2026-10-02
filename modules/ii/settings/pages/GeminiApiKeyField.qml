pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Gemini API key editor for the wallpaper-based clock styling.
 * The key lives in the system keyring (KeyringStorage, apiKeys.gemini) and is
 * never shown pre-filled: the field is only for typing a new one.
 */
ColumnLayout {
    id: root
    spacing: 8

    readonly property string savedKey: KeyringStorage.keyringData?.apiKeys?.gemini ?? ""
    readonly property bool hasKey: savedKey.length > 0
    property bool revealed: false
    // "", "testing", "ok", "invalid", "error"
    property string testState: ""
    property string testDetail: ""

    Component.onCompleted: {
        if (!KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
    }

    function save() {
        const key = keyField.text.trim();
        if (key.length === 0) return;
        KeyringStorage.setNestedFieldSafely(["apiKeys", "gemini"], key);
        keyField.text = "";
        root.revealed = false;
        testAfterSave.restart();
    }

    function remove() {
        KeyringStorage.setNestedFieldSafely(["apiKeys", "gemini"], "");
        root.testState = "";
    }

    function test(key) {
        const k = (key ?? root.savedKey).trim();
        if (k.length === 0) return;
        root.testState = "testing";
        root.testDetail = "";
        // Key goes through the environment, never on the command line
        tester.environment = { "GEMINI_TEST_KEY": k };
        tester.running = true;
    }

    // Give the keyring a moment to store before testing the saved key
    Timer {
        id: testAfterSave
        interval: 400
        onTriggered: root.test()
    }

    Process {
        id: tester
        command: ["bash", "-c", "curl -s -m 15 -o /dev/null -w '%{http_code}' -H \"x-goog-api-key: $GEMINI_TEST_KEY\" 'https://generativelanguage.googleapis.com/v1beta/models?pageSize=1'"]
        stdout: StdioCollector {
            id: testerOutput
            onStreamFinished: {
                const code = parseInt(testerOutput.text.trim());
                if (code === 200) {
                    root.testState = "ok";
                } else if (code === 400 || code === 401 || code === 403) {
                    root.testState = "invalid";
                    root.testDetail = `HTTP ${code}`;
                } else {
                    root.testState = "error";
                    root.testDetail = isNaN(code) || code === 0 ? Translation.tr("no connection") : `HTTP ${code}`;
                }
            }
        }
    }

    // Status line
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10

        MaterialSymbol {
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSecondaryContainer
            text: !KeyringStorage.loaded ? "lock" : root.hasKey ? "key" : "key_off"
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                text: Translation.tr("Gemini API key")
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: root.testState === "invalid" || root.testState === "error"
                    ? Appearance.colors.colError : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: {
                    if (!KeyringStorage.loaded) return Translation.tr("Keyring locked or not loaded yet");
                    switch (root.testState) {
                        case "testing": return Translation.tr("Testing key…");
                        case "ok": return Translation.tr("Saved · working");
                        case "invalid": return Translation.tr("Saved · rejected by Google (%1). Paste a new key below").arg(root.testDetail);
                        case "error": return Translation.tr("Saved · could not test (%1)").arg(root.testDetail);
                    }
                    return root.hasKey ? Translation.tr("Saved in the system keyring") : Translation.tr("Not set");
                }
            }
        }
        RippleButton {
            visible: root.hasKey
            enabled: root.testState !== "testing"
            implicitHeight: 32
            implicitWidth: testLabel.implicitWidth + 24
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            onClicked: root.test()
            contentItem: StyledText {
                id: testLabel
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Test")
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
        RippleButton {
            visible: root.hasKey
            implicitHeight: 32
            implicitWidth: 32
            buttonRadius: Appearance.rounding.full
            onClicked: root.remove()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                iconSize: Appearance.font.pixelSize.larger
                text: "delete"
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledToolTip {
                text: Translation.tr("Remove saved key")
            }
        }
    }

    // Input row
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 6

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2
            border.width: keyField.activeFocus ? 1 : 0
            border.color: Appearance.colors.colPrimary

            TextInput {
                id: keyField
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 38
                verticalAlignment: TextInput.AlignVCenter
                color: Appearance.colors.colOnLayer1
                selectionColor: Appearance.colors.colSecondaryContainer
                selectedTextColor: Appearance.colors.colOnSecondaryContainer
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                clip: true
                echoMode: root.revealed ? TextInput.Normal : TextInput.Password
                onAccepted: root.save()

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: keyField.text.length === 0
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: root.hasKey ? Translation.tr("Paste a new key to replace the saved one") : Translation.tr("Paste your Gemini API key")
                }
            }

            MaterialSymbol {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                iconSize: Appearance.font.pixelSize.larger
                text: root.revealed ? "visibility_off" : "visibility"
                color: Appearance.colors.colSubtext
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.revealed = !root.revealed
                }
            }
        }

        RippleButton {
            enabled: keyField.text.trim().length > 0
            opacity: enabled ? 1 : 0.5
            implicitHeight: 38
            implicitWidth: saveLabel.implicitWidth + 28
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            onClicked: root.save()
            contentItem: StyledText {
                id: saveLabel
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Save")
                color: Appearance.colors.colOnPrimary
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    // Help
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 4
        wrapMode: Text.Wrap
        textFormat: Text.StyledText
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.smaller
        linkColor: Appearance.colors.colPrimary
        text: Translation.tr("Get a free key at <a href=\"https://aistudio.google.com/app/apikey\">aistudio.google.com</a>. Free tier data may be used for training. Only a 200px thumbnail of the wallpaper is sent.")
        onLinkActivated: link => Qt.openUrlExternally(link)
        PointingHandLinkHover {}
    }
}
