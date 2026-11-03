import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Ollama card: is the server running (and who started it), is the GPU used, and on which
 * disk the models are stored.
 */
AiPopup {
    id: root
    title: Translation.tr("Ollama")
    icon: "dns"

    property var pendingDisk: null     // disk row picked but not applied yet
    property bool moveExisting: true

    readonly property var health: Ai.ollamaHealth
    readonly property bool running: health.running === true
    readonly property bool busy: Ai.ollamaBusy !== ""
    readonly property var currentFolder: Ai.ollamaFound.find(f => f.path === Ai.ollamaModelsDir) ?? null

    function formatBytes(n) {
        if (!n || n <= 0) return "0 GB";
        const gb = n / (1024 * 1024 * 1024);
        return gb >= 100 ? `${Math.round(gb)} GB` : gb >= 1 ? `${gb.toFixed(1)} GB` : `${Math.round(n / (1024 * 1024))} MB`;
    }

    onOpenChanged: {
        root.pendingDisk = null;
        if (open) {
            Ai.refreshOllamaHealth();
            Ai.refreshOllamaDisks();
        }
    }

    headerActions: [
        RippleButton {
            implicitWidth: 30
            implicitHeight: 30
            topPadding: 0
            bottomPadding: 0
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            onClicked: {
                Ai.refreshOllamaHealth();
                Ai.refreshOllamaDisks();
                Ai.refreshLocalModels();
            }
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "sync"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer3
            }
            StyledToolTip { text: Translation.tr("Refresh") }
        }
    ]

    component SectionTitle: RowLayout {
        id: sectionTitle
        property string symbol
        property string text
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 6
        MaterialSymbol {
            text: sectionTitle.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            text: sectionTitle.text
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Medium
            color: Appearance.colors.colPrimary
        }
    }

    component InfoPill: Rectangle {
        id: pill
        property string text
        property color fg: Appearance.colors.colOnSecondaryContainer
        implicitHeight: 20
        implicitWidth: pillText.implicitWidth + 14
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        StyledText {
            id: pillText
            anchors.centerIn: parent
            text: pill.text
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: pill.fg
        }
    }

    component Card: Rectangle {
        Layout.fillWidth: true
        implicitHeight: cardContent.implicitHeight + 20
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2
        default property alias content: cardContent.data
        ColumnLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
        }
    }

    component SmallButton: RippleButton {
        id: smallButton
        property string symbol
        property string label
        property bool primary: false
        implicitHeight: 32
        implicitWidth: sbRow.implicitWidth + 20
        topPadding: 0
        bottomPadding: 0
        buttonRadius: Appearance.rounding.small
        colBackground: primary ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
        colBackgroundHover: primary ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer3Hover
        contentItem: RowLayout {
            id: sbRow
            spacing: 5
            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: smallButton.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: smallButton.primary ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.bottomMargin: 2
                text: smallButton.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: smallButton.primary ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
            }
        }
    }

    Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: body.implicitHeight
        Layout.minimumHeight: Math.min(body.implicitHeight, 120)
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 8

            // ------------------------------------------------ Server
            SectionTitle { symbol: "power"; text: Translation.tr("Server") }
            Card {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 10
                        implicitHeight: 10
                        radius: 5
                        color: root.running ? Appearance.colors.colPrimary : Appearance.colors.colError
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                            text: {
                                if (root.health.installed === false) return Translation.tr("Not installed");
                                if (Ai.ollamaBusy === "starting") return Translation.tr("Starting…");
                                if (Ai.ollamaBusy === "stopping") return Translation.tr("Stopping…");
                                if (!root.running) return Translation.tr("Stopped");
                                return Translation.tr("Running · version %1").arg(root.health.version ?? "");
                            }
                        }
                        StyledText {
                            visible: root.running
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: root.health.owner === "shell" ? Translation.tr("Started by the shell")
                                : root.health.owner === "system" ? Translation.tr("System service (ollama.service)")
                                : Translation.tr("Started outside the shell")
                        }
                    }
                    SmallButton {
                        visible: !root.running && root.health.installed !== false
                        enabled: !root.busy
                        primary: true
                        symbol: "play_arrow"
                        label: Translation.tr("Start")
                        onClicked: Ai.startOllama()
                    }
                    SmallButton {
                        visible: root.running && root.health.owner === "shell"
                        enabled: !root.busy
                        symbol: "restart_alt"
                        label: Translation.tr("Restart")
                        onClicked: Ai.restartOllama()
                    }
                    SmallButton {
                        visible: root.running && root.health.owner === "shell"
                        enabled: !root.busy
                        symbol: "stop"
                        label: Translation.tr("Stop")
                        onClicked: Ai.stopOllama()
                    }
                }

                StyledText {
                    visible: root.running && root.health.owner !== "shell"
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: root.health.owner === "system"
                        ? Translation.tr("The shell only stops servers it started itself. To stop this one: `sudo systemctl stop ollama`.")
                        : Translation.tr("The shell only stops servers it started itself. Stop it where you started it.")
                }
                StyledText {
                    visible: root.health.installed === false
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Install it with `sudo pacman -S ollama`.")
                }

                // Error / result of the last action
                StyledText {
                    visible: Ai.ollamaMessage.length > 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                    text: Ai.ollamaMessage
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                        text: Translation.tr("Start Ollama together with the shell")
                    }
                    StyledSwitch {
                        checked: Config.options.ai.ollama.autostart
                        onClicked: Config.options.ai.ollama.autostart = checked
                    }
                }
            }

            // ------------------------------------------------ GPU
            SectionTitle { symbol: "memory"; text: Translation.tr("Acceleration") }
            Card {
                // GPUs the running server picked (read from its own log)
                Repeater {
                    model: root.health.devices ?? []
                    delegate: RowLayout {
                        id: devRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: devRow.modelData.library.toLowerCase() === "cpu" ? "developer_board" : "memory"
                            fill: 1
                            iconSize: Appearance.font.pixelSize.huge
                            color: devRow.modelData.library.toLowerCase() === "cpu" ? Appearance.colors.colSubtext : Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer2
                                text: devRow.modelData.name
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("%1 · %2 free of %3").arg(devRow.modelData.library)
                                    .arg(root.formatBytes(devRow.modelData.available)).arg(root.formatBytes(devRow.modelData.total))
                            }
                        }
                        InfoPill {
                            Layout.alignment: Qt.AlignVCenter
                            text: Translation.tr("In use")
                            fg: Appearance.colors.colOnPrimaryContainer
                            color: Appearance.colors.colPrimaryContainer
                        }
                    }
                }

                // Nothing read from the log: show the GPU found on the PC
                RowLayout {
                    visible: (root.health.devices ?? []).length === 0 && (root.health.gpus ?? []).length > 0
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: "memory"
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                            text: {
                                const g = (root.health.gpus ?? [])[0];
                                if (!g) return "";
                                return g.vram > 0 ? `${g.name} · ${root.formatBytes(g.vram)}` : g.name;
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                            text: root.running && root.health.owner !== "shell"
                                ? (root.health.loadedOnGpu ? Translation.tr("A loaded model is using the GPU.") : Translation.tr("Load a model to see whether it uses the GPU."))
                                : Translation.tr("Start Ollama from here to see which GPU it picks.")
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: Translation.tr("Installed backends")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    Repeater {
                        model: root.health.runners ?? []
                        delegate: InfoPill {
                            required property string modelData
                            text: modelData === "rocm" ? "ROCm" : modelData === "cuda" ? "CUDA" : modelData === "vulkan" ? "Vulkan" : "CPU"
                        }
                    }
                    Item { Layout.fillWidth: true }
                }

                // Install suggestion or "GPU not found"
                Rectangle {
                    visible: root.health.hint !== null && root.health.hint !== undefined
                    Layout.fillWidth: true
                    implicitHeight: hintCol.implicitHeight + 16
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colTertiaryContainer
                    ColumnLayout {
                        id: hintCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.m3colors.m3onTertiaryContainer
                            text: root.health.hint?.kind === "install"
                                ? Translation.tr("Ollama only has the CPU backend, so models run slowly. Install the %1 package to use your GPU:").arg(root.health.hint?.package ?? "")
                                : Translation.tr("Ollama is running on the CPU although the PC has a GPU. Check the backend packages and the GPU driver.")
                        }
                        RowLayout {
                            visible: (root.health.hint?.command ?? "").length > 0
                            Layout.fillWidth: true
                            spacing: 6
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                font.family: Appearance.font.family.monospace
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.m3colors.m3onTertiaryContainer
                                text: root.health.hint?.command ?? ""
                            }
                            SmallButton {
                                symbol: "content_copy"
                                label: Translation.tr("Copy")
                                onClicked: Quickshell.clipboardText = root.health.hint?.command ?? ""
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------ Disk
            SectionTitle { symbol: "hard_drive"; text: Translation.tr("Where the models are stored") }
            Card {
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Now: %1").arg(Ai.ollamaModelsDir)
                }

                Repeater {
                    model: Ai.ollamaDisks
                    delegate: Rectangle {
                        id: diskRow
                        required property var modelData
                        readonly property bool isCurrent: modelData.path === Ai.ollamaModelsDir
                        readonly property bool isPending: root.pendingDisk !== null && root.pendingDisk.path === modelData.path
                        readonly property real usedFraction: modelData.size > 0 ? 1 - modelData.free / modelData.size : 0
                        Layout.fillWidth: true
                        implicitHeight: diskCol.implicitHeight + 16
                        radius: Appearance.rounding.small
                        color: isPending ? Appearance.colors.colPrimaryContainer
                            : isCurrent ? Appearance.colors.colSecondaryContainer
                            : diskMouse.containsMouse ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
                        opacity: modelData.writable ? 1 : 0.5

                        MouseArea {
                            id: diskMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: diskRow.modelData.writable && !root.busy && !diskRow.isCurrent
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.pendingDisk = diskRow.isPending ? null : diskRow.modelData
                        }

                        ColumnLayout {
                            id: diskCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                MaterialSymbol {
                                    text: diskRow.modelData.kind === "USB" ? "usb" : diskRow.modelData.kind === "HDD" ? "hard_drive" : "storage"
                                    iconSize: Appearance.font.pixelSize.huge
                                    color: Appearance.colors.colOnLayer3
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer3
                                        text: `${diskRow.modelData.kind} ${root.formatBytes(diskRow.modelData.size)}` + (diskRow.modelData.model ? ` · ${diskRow.modelData.model}` : "")
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideMiddle
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: Appearance.colors.colSubtext
                                        text: diskRow.modelData.path
                                    }
                                }
                                InfoPill {
                                    visible: diskRow.isCurrent
                                    text: Translation.tr("In use")
                                    fg: Appearance.colors.colOnPrimaryContainer
                                    color: Appearance.colors.colPrimaryContainer
                                }
                                InfoPill {
                                    visible: diskRow.modelData.system && !diskRow.isCurrent
                                    text: Translation.tr("System")
                                }
                                InfoPill {
                                    visible: diskRow.modelData.encrypted
                                    text: Translation.tr("Encrypted")
                                }
                            }
                            // Free space bar
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 6
                                radius: 3
                                color: Appearance.colors.colSecondaryContainer
                                Rectangle {
                                    width: parent.width * Math.min(1, Math.max(0, diskRow.usedFraction))
                                    height: parent.height
                                    radius: 3
                                    color: diskRow.usedFraction > 0.9 ? Appearance.colors.colError : Appearance.colors.colPrimary
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                text: diskRow.modelData.writable
                                    ? Translation.tr("%1 free of %2").arg(root.formatBytes(diskRow.modelData.free)).arg(root.formatBytes(diskRow.modelData.size))
                                    : Translation.tr("Not writable by your user")
                            }
                        }
                    }
                }

                StyledText {
                    visible: Ai.ollamaDisks.length === 0
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Looking for disks…")
                }

                // Confirm the change
                ColumnLayout {
                    visible: root.pendingDisk !== null && !root.busy
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                        text: root.running
                            ? Translation.tr("New models will go to %1. Ollama restarts, so loaded models are unloaded.").arg(root.pendingDisk?.path ?? "")
                            : Translation.tr("New models will go to %1.").arg(root.pendingDisk?.path ?? "")
                    }
                    RowLayout {
                        visible: root.currentFolder !== null && root.currentFolder.models > 0
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                            text: Translation.tr("Move the %1 installed models (%2) to the new disk").arg(root.currentFolder?.models ?? 0).arg(root.formatBytes(root.currentFolder?.bytes ?? 0))
                        }
                        StyledSwitch {
                            checked: root.moveExisting
                            onClicked: root.moveExisting = checked
                        }
                    }
                    StyledText {
                        visible: root.running && root.health.owner !== "shell"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colError
                        text: Translation.tr("This Ollama was not started by the shell. Stop it first.")
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Item { Layout.fillWidth: true }
                        SmallButton {
                            symbol: "close"
                            label: Translation.tr("Cancel")
                            onClicked: root.pendingDisk = null
                        }
                        SmallButton {
                            primary: true
                            enabled: !(root.running && root.health.owner !== "shell")
                            symbol: "check"
                            label: Translation.tr("Use this disk")
                            onClicked: {
                                const d = root.pendingDisk;
                                const move = root.moveExisting && root.currentFolder !== null && root.currentFolder.models > 0;
                                root.pendingDisk = null;
                                Ai.setModelsDisk(d.path, d.system ? "" : d.mount, move);
                            }
                        }
                    }
                }

                // Moving models
                ColumnLayout {
                    visible: Ai.ollamaBusy === "moving"
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                        text: Translation.tr("Copying models… %1%").arg(Math.round(Ai.ollamaMoveProgress * 100))
                    }
                    StyledProgressBar {
                        Layout.fillWidth: true
                        valueBarWidth: 200
                        value: Ai.ollamaMoveProgress
                    }
                }
            }
        }
    }
}
