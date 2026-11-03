import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Local model chooser: every installed Ollama / vLLM model with its size, quantization,
 * capabilities and whether it is loaded in VRAM. Click a row to use that model.
 */
AiPopup {
    id: root
    title: Translation.tr("Local models")
    icon: "neurology"

    property string confirmDelete: "" // raw name of the model waiting for a second click
    signal manageRequested()
    signal catalogRequested()

    function formatBytes(n) {
        if (!n || n <= 0) return "";
        const gb = n / (1024 * 1024 * 1024);
        return gb >= 1 ? `${gb.toFixed(1)} GB` : `${Math.round(n / (1024 * 1024))} MB`;
    }

    onOpenChanged: {
        root.confirmDelete = "";
        if (open) Ai.refreshLocalModels();
    }

    headerActions: [
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            topPadding: 0
            bottomPadding: 0
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            onClicked: root.manageRequested()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "settings"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
            }
            StyledToolTip { text: Translation.tr("Ollama server, GPU and model disk") }
        },
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            topPadding: 0
            bottomPadding: 0
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            onClicked: Ai.refreshLocalModels()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "sync"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
            }
            StyledToolTip { text: Translation.tr("Rescan local models") }
        }
    ]

    component Badge: Rectangle {
        id: badge
        property string icon
        property string text
        property color fg: Appearance.colors.colOnSecondaryContainer
        implicitHeight: 20
        implicitWidth: badgeRow.implicitWidth + 12
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        RowLayout {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 3
            MaterialSymbol {
                text: badge.icon
                iconSize: Appearance.font.pixelSize.small
                color: badge.fg
            }
            StyledText {
                text: badge.text
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: badge.fg
            }
        }
    }

    // Ollama status line
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 8
            implicitHeight: 8
            radius: 4
            color: Ai.ollamaRunning ? Appearance.colors.colPrimary : Appearance.colors.colError
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            text: {
                if (Ai.ollamaBusy === "starting") return Translation.tr("Starting Ollama…");
                if (!Ai.ollamaRunning)
                    return Translation.tr("Ollama is not running.");
                const infos = Object.values(Ai.ollamaInfo);
                const loaded = infos.filter(i => i.loaded).length;
                return Translation.tr("Ollama %1 running · %2 installed · %3 loaded").arg(Ai.ollamaVersion).arg(infos.length).arg(loaded);
            }
        }
    }

    RippleButton {
        visible: !Ai.ollamaRunning && Ai.ollamaHealth.installed !== false
        enabled: Ai.ollamaBusy === ""
        Layout.fillWidth: true
        implicitHeight: 34
        topPadding: 0
        bottomPadding: 0
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colPrimaryContainer
        colBackgroundHover: Appearance.colors.colPrimaryContainerHover
        onClicked: Ai.startOllama()
        contentItem: RowLayout {
            spacing: 6
            Item { Layout.fillWidth: true }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "play_arrow"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnPrimaryContainer
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.bottomMargin: 2
                text: Translation.tr("Start Ollama")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnPrimaryContainer
            }
            Item { Layout.fillWidth: true }
        }
    }

    StyledText {
        visible: Ai.modelList.length === 0
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.bottomMargin: 6
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: Translation.tr("No local model found.\nPull one with `ollama pull llama3.2`, then rescan.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }

    ListView {
        id: list
        visible: Ai.modelList.length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: contentHeight
        Layout.minimumHeight: Math.min(contentHeight, 70)
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}
        model: Ai.modelList

        delegate: Rectangle {
            id: row
            required property string modelData
            readonly property var aiModel: Ai.models[modelData]
            readonly property var info: Ai.ollamaInfo[aiModel?.model ?? ""] ?? null
            readonly property bool active: Ai.currentModelId === modelData
            readonly property bool confirming: info !== null && root.confirmDelete === info.name
            readonly property bool chatCapable: Ai.isChatModel(modelData)
            width: ListView.view.width
            implicitHeight: rowLayout.implicitHeight + 16
            opacity: chatCapable ? 1 : 0.7
            radius: Appearance.rounding.small
            color: active ? Appearance.colors.colSecondaryContainer
                : rowMouse.containsMouse && chatCapable ? Appearance.colors.colLayer3Hover : "transparent"

            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: row.chatCapable
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Ai.setModel(row.modelData, false);
                    root.close();
                }
            }

            RowLayout {
                id: rowLayout
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10

                CustomIcon {
                    Layout.alignment: Qt.AlignTop
                    width: 26
                    height: 26
                    source: row.aiModel?.icon ?? ""
                    colorize: true
                    color: row.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: row.aiModel?.name ?? row.modelData
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: row.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: {
                            if (!row.info) return row.aiModel?.model ?? "";
                            const parts = [row.info.name];
                            if (row.info.parameterSize) parts.push(row.info.parameterSize);
                            if (row.info.quantization) parts.push(row.info.quantization);
                            const size = root.formatBytes(row.info.size);
                            if (size) parts.push(size);
                            return parts.join(" · ");
                        }
                    }
                    Flow {
                        visible: row.info !== null
                        Layout.fillWidth: true
                        spacing: 4
                        Badge {
                            visible: row.info?.loaded ?? false
                            icon: "memory"
                            text: Translation.tr("Loaded %1").arg(root.formatBytes(row.info?.sizeVram ?? 0))
                            color: Appearance.colors.colPrimaryContainer
                            fg: Appearance.colors.colOnPrimaryContainer
                        }
                        Badge {
                            visible: !row.chatCapable
                            icon: "data_array"
                            text: Translation.tr("Embedding (not for chat)")
                            color: Appearance.colors.colTertiaryContainer
                            fg: Appearance.m3colors.m3onTertiaryContainer
                        }
                        Badge {
                            visible: (row.info?.capabilities ?? []).includes("tools")
                            icon: "service_toolbox"
                            text: Translation.tr("Tools")
                        }
                        Badge {
                            visible: (row.info?.capabilities ?? []).includes("vision")
                            icon: "visibility"
                            text: Translation.tr("Vision")
                        }
                        Badge {
                            visible: (row.info?.capabilities ?? []).includes("thinking")
                            icon: "psychology"
                            text: Translation.tr("Thinking")
                        }
                        Badge {
                            visible: (row.info?.contextLength ?? 0) > 0
                            icon: "text_fields"
                            text: (row.info?.contextLength ?? 0) >= 1024 ? Translation.tr("%1k ctx").arg(Math.round(row.info.contextLength / 1024)) : Translation.tr("%1 ctx").arg(row.info?.contextLength ?? 0)
                        }
                    }
                }

                // Free VRAM (model stays installed)
                RippleButton {
                    visible: row.info?.loaded ?? false
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    onClicked: Ai.unloadOllamaModel(row.info.name)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "eject"
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledToolTip { text: Translation.tr("Unload from memory (keeps it installed)") }
                }

                // Delete from disk: asks for a second click
                RippleButton {
                    visible: row.info !== null
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: row.confirming ? deleteRow.implicitWidth + 16 : 30
                    implicitHeight: 30
                    topPadding: 0
                    bottomPadding: 0
                    buttonRadius: Appearance.rounding.full
                    colBackground: row.confirming ? Appearance.colors.colErrorContainer : "transparent"
                    colBackgroundHover: row.confirming ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer3Hover
                    onClicked: {
                        if (row.confirming) {
                            root.confirmDelete = "";
                            Ai.deleteOllamaModel(row.info.name);
                        } else {
                            root.confirmDelete = row.info.name;
                        }
                    }
                    contentItem: RowLayout {
                        id: deleteRow
                        spacing: 4
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: row.confirming ? "delete_forever" : "delete"
                            iconSize: Appearance.font.pixelSize.larger
                            color: row.confirming ? Appearance.m3colors.m3onErrorContainer : Appearance.colors.colOnLayer3
                        }
                        StyledText {
                            visible: row.confirming
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("Delete?")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3onErrorContainer
                        }
                    }
                    StyledToolTip {
                        text: row.confirming
                            ? Translation.tr("Click again to remove %1 from disk").arg(row.info?.name ?? "")
                            : Translation.tr("Delete this model from disk")
                    }
                }

                MaterialSymbol {
                    visible: row.active
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 3
                    text: "check_circle"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
        }
    }

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 36
        topPadding: 0
        bottomPadding: 0
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: root.catalogRequested()
        contentItem: RowLayout {
            spacing: 6
            Item { Layout.fillWidth: true }
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "download"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.bottomMargin: 2
                text: Translation.tr("Browse and download models")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            Item { Layout.fillWidth: true }
        }
        StyledToolTip { text: Translation.tr("Ranked for your PC: best models first") }
    }
}
