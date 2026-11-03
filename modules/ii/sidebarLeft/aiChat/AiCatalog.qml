import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Model catalog: every model of the Ollama library, ranked for THIS PC (GPU memory, RAM, the
 * context size you use), with a download button per model. Best first or worst first.
 */
Item {
    id: root
    property bool open: false
    property bool bestFirst: true
    property string query: ""
    property string filterKey: "all"     // all | tools | vision | thinking | code | embedding
    property bool gpuOnly: false
    signal closed()
    signal manageRequested()

    function show() {
        root.open = true;
        Ai.openCatalog();
        searchField.forceActiveFocus();
    }
    function close() {
        if (!root.open) return;
        root.open = false;
        root.closed();
    }

    z: 15
    visible: opacity > 0
    opacity: root.open ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    readonly property var hw: Ai.catalog.hardware ?? ({})
    readonly property var allVariants: Ai.catalog.variants ?? []

    // Filter + order. Embedding models only show under their own filter (they can't chat).
    readonly property var rows: {
        const q = root.query.trim().toLowerCase();
        let list = root.allVariants.filter(v => {
            if (root.filterKey === "embedding") return v.embedding;
            if (v.embedding) return false;
            if (root.filterKey !== "all" && !v.capabilities.includes(root.filterKey)) return false;
            if (root.gpuOnly && v.fit !== "gpu") return false;
            if (q.length > 0 && !(`${v.id} ${v.description}`.toLowerCase().includes(q))) return false;
            return true;
        });
        if (root.filterKey === "embedding" && q.length > 0) list = list.filter(v => `${v.id} ${v.description}`.toLowerCase().includes(q));
        return root.bestFirst ? list : list.slice().reverse();
    }

    function formatGb(gb) {
        return gb >= 100 ? `${Math.round(gb)} GB` : gb >= 10 ? `${gb.toFixed(0)} GB` : `${gb.toFixed(1)} GB`;
    }
    function formatBytes(n) {
        return n >= 1024 * 1024 * 1024 ? root.formatGb(n / (1024 * 1024 * 1024)) : `${Math.round(n / (1024 * 1024))} MB`;
    }
    function ageText(ts) {
        if (!ts) return "";
        const mins = Math.max(0, Math.round((Date.now() / 1000 - ts) / 60));
        if (mins < 60) return Translation.tr("%1 min ago").arg(mins);
        if (mins < 60 * 48) return Translation.tr("%1 h ago").arg(Math.round(mins / 60));
        return Translation.tr("%1 days ago").arg(Math.round(mins / 1440));
    }
    function isInstalled(id) {
        return Ai.ollamaInfo[id] !== undefined || (id.endsWith(":latest") && Object.keys(Ai.ollamaInfo).includes(id));
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer1Base // opaque: the chat must not show through
        MouseArea { anchors.fill: parent } // swallow clicks
    }

    component Chip: RippleButton {
        id: chip
        property string symbol
        property string label
        property bool active: false
        implicitHeight: 28
        implicitWidth: chipRow.implicitWidth + 18
        topPadding: 0
        bottomPadding: 0
        buttonRadius: Appearance.rounding.small
        toggled: active
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        contentItem: RowLayout {
            id: chipRow
            spacing: 4
            MaterialSymbol {
                visible: chip.symbol.length > 0
                Layout.alignment: Qt.AlignVCenter
                text: chip.symbol
                iconSize: Appearance.font.pixelSize.larger
                color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                Layout.bottomMargin: 2
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
        }
    }

    component Tag: Rectangle {
        id: tag
        property string text
        property string symbol
        property color fg: Appearance.colors.colOnSecondaryContainer
        implicitHeight: 20
        implicitWidth: tagRow.implicitWidth + 12
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        RowLayout {
            id: tagRow
            anchors.centerIn: parent
            spacing: 3
            MaterialSymbol {
                visible: tag.symbol.length > 0
                text: tag.symbol
                iconSize: Appearance.font.pixelSize.small
                color: tag.fg
            }
            StyledText {
                Layout.bottomMargin: 1
                text: tag.text
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: tag.fg
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        // ---- Header
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                topPadding: 0
                bottomPadding: 0
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: root.close()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.huge
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Back to the chat") }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Model catalog")
                font.pixelSize: Appearance.font.pixelSize.title
                color: Appearance.colors.colOnLayer1
            }
            Chip {
                symbol: root.bestFirst ? "trending_down" : "trending_up"
                label: root.bestFirst ? Translation.tr("Best first") : Translation.tr("Worst first")
                onClicked: root.bestFirst = !root.bestFirst
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                topPadding: 0
                bottomPadding: 0
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                onClicked: Ai.loadCatalog(true)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "sync"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip { text: Translation.tr("Update the list from ollama.com") }
            }
        }

        // ---- This PC + where models go
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: pcCol.implicitHeight + 16
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            ColumnLayout {
                id: pcCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "memory"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                        text: root.hw.gpuName
                            ? Translation.tr("%1 · %2 VRAM · %3 RAM").arg(root.hw.gpuName).arg(root.formatGb(root.hw.vramGb ?? 0)).arg(root.formatGb(root.hw.ramGb ?? 0))
                            : Translation.tr("No dedicated GPU found · %1 RAM · models will run on the CPU").arg(root.formatGb(root.hw.ramGb ?? 0))
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        text: Translation.tr("Context")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                        Layout.rightMargin: 2
                    }
                    Repeater {
                        model: [4096, 8192, 16384, 32768, 65536]
                        delegate: Chip {
                            required property int modelData
                            label: `${modelData / 1024}k`
                            active: Ai.catalogCtx === modelData
                            onClicked: Ai.setCatalogCtx(modelData)
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: Ai.modelsDiskFree >= 0
                            ? Translation.tr("Downloads go to %1 (%2 free)").arg(Ai.ollamaModelsDir).arg(root.formatBytes(Ai.modelsDiskFree))
                            : Translation.tr("Downloads go to %1").arg(Ai.ollamaModelsDir)
                    }
                    RippleButton {
                        implicitHeight: 26
                        implicitWidth: changeRow.implicitWidth + 16
                        topPadding: 0
                        bottomPadding: 0
                        buttonRadius: Appearance.rounding.small
                        colBackground: Appearance.colors.colLayer3
                        colBackgroundHover: Appearance.colors.colLayer3Hover
                        onClicked: root.manageRequested()
                        contentItem: RowLayout {
                            id: changeRow
                            spacing: 4
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "hard_drive"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnLayer3
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.bottomMargin: 2
                                text: Translation.tr("Change disk")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnLayer3
                            }
                        }
                    }
                }
            }
        }

        // ---- Search + filters
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 38
            radius: Appearance.rounding.small
            color: Appearance.colors.colLayer2
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "search"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
                StyledTextInput {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    color: Appearance.colors.colOnLayer2
                    onTextChanged: root.query = text
                    StyledText {
                        visible: searchField.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Search models (name or description)")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [
                    { key: "all", symbol: "apps", label: Translation.tr("All") },
                    { key: "tools", symbol: "service_toolbox", label: Translation.tr("Tools") },
                    { key: "vision", symbol: "visibility", label: Translation.tr("Vision") },
                    { key: "thinking", symbol: "psychology", label: Translation.tr("Thinking") },
                    { key: "code", symbol: "code", label: Translation.tr("Code") },
                    { key: "embedding", symbol: "data_array", label: Translation.tr("Embedding") }
                ]
                delegate: Chip {
                    required property var modelData
                    symbol: modelData.symbol
                    label: modelData.label
                    active: root.filterKey === modelData.key
                    onClicked: root.filterKey = modelData.key
                }
            }
            Chip {
                symbol: "memory"
                label: Translation.tr("Fits the GPU")
                active: root.gpuOnly
                onClicked: root.gpuOnly = !root.gpuOnly
            }
        }

        // ---- Status line
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: {
                    if (Ai.catalogLoading && root.allVariants.length === 0) return Translation.tr("Loading the catalog…");
                    if (Ai.catalogError.length > 0 && root.allVariants.length === 0) return Ai.catalogError;
                    const src = Ai.catalog.source === "bundled" ? Translation.tr("offline list")
                        : Translation.tr("ollama.com, %1").arg(root.ageText(Ai.catalog.fetchedAt));
                    const est = root.allVariants.length - (Ai.catalog.exactSizes ?? 0);
                    return Translation.tr("%1 shown · sizes: %2 exact, %3 estimated · %4").arg(root.rows.length).arg(Ai.catalog.exactSizes ?? 0).arg(est).arg(src);
                }
            }
            StyledText {
                visible: Ai.refineTotal > 0
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colPrimary
                text: Translation.tr("Reading sizes %1/%2").arg(Math.round(Ai.refineDone)).arg(Math.round(Ai.refineTotal))
            }
        }
        StyledIndeterminateProgressBar {
            visible: Ai.catalogLoading
            Layout.fillWidth: true
        }

        // ---- The ranked list
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 600
            ScrollBar.vertical: StyledScrollBar {}
            model: root.rows

            StyledText {
                visible: root.rows.length === 0 && !Ai.catalogLoading
                anchors.centerIn: parent
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Translation.tr("No model matches these filters.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var pull: Ai.pulls[modelData.id] ?? null
                readonly property bool installed: root.isInstalled(modelData.id) || pull?.state === "done"
                readonly property bool noDiskSpace: Ai.modelsDiskFree >= 0 && modelData.sizeGb * 1.05 * 1024 * 1024 * 1024 > Ai.modelsDiskFree
                readonly property color fitColor: modelData.fit === "gpu" ? Appearance.colors.colPrimaryContainer
                    : modelData.fit === "partial" ? Appearance.colors.colTertiaryContainer
                    : modelData.fit === "cpu" ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colErrorContainer
                readonly property color fitTextColor: modelData.fit === "gpu" ? Appearance.colors.colOnPrimaryContainer
                    : modelData.fit === "partial" ? Appearance.m3colors.m3onTertiaryContainer
                    : modelData.fit === "cpu" ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.m3colors.m3onErrorContainer
                width: ListView.view.width
                implicitHeight: rowLayout.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: rowLayout
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    StyledText {
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: 30
                        horizontalAlignment: Text.AlignHCenter
                        text: row.modelData.rank !== null && row.modelData.rank !== undefined ? `#${row.modelData.rank}` : "–"
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: row.modelData.rank !== null && row.modelData.rank <= 3 ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: row.modelData.id
                            font.pixelSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            text: row.modelData.description
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 4
                            Tag {
                                color: row.fitColor
                                fg: row.fitTextColor
                                symbol: row.modelData.fit === "gpu" ? "memory" : row.modelData.fit === "partial" ? "swap_horiz" : row.modelData.fit === "cpu" ? "developer_board" : "block"
                                text: row.modelData.fit === "gpu" ? Translation.tr("Fits the GPU")
                                    : row.modelData.fit === "partial" ? Translation.tr("GPU + RAM")
                                    : row.modelData.fit === "cpu" ? Translation.tr("CPU only")
                                    : Translation.tr("Too big")
                            }
                            Tag {
                                visible: row.modelData.fit !== "no"
                                symbol: "speed"
                                text: Translation.tr("≈ %1 tok/s").arg(Math.round(row.modelData.tps))
                            }
                            Tag {
                                symbol: "database"
                                text: `${row.modelData.sizeExact ? "" : "≈ "}${root.formatGb(row.modelData.sizeGb)}`
                            }
                            Tag {
                                visible: row.modelData.moe
                                text: Translation.tr("MoE")
                            }
                            Tag {
                                visible: row.modelData.capabilities.includes("tools")
                                symbol: "service_toolbox"
                                text: Translation.tr("Tools")
                            }
                            Tag {
                                visible: row.modelData.capabilities.includes("vision")
                                symbol: "visibility"
                                text: Translation.tr("Vision")
                            }
                            Tag {
                                visible: row.modelData.capabilities.includes("thinking")
                                symbol: "psychology"
                                text: Translation.tr("Thinking")
                            }
                            Tag {
                                visible: row.modelData.capabilities.includes("code")
                                symbol: "code"
                                text: Translation.tr("Code")
                            }
                        }
                        // Progress
                        ColumnLayout {
                            visible: row.pull?.state === "pulling"
                            Layout.fillWidth: true
                            spacing: 2
                            StyledProgressBar {
                                Layout.fillWidth: true
                                valueBarWidth: 200
                                value: (row.pull?.percent ?? 0) / 100
                            }
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: Translation.tr("%1 of %2 · %3/s").arg(root.formatBytes(row.pull?.completed ?? 0)).arg(root.formatBytes(row.pull?.total ?? 0)).arg(root.formatBytes(row.pull?.speed ?? 0))
                            }
                        }
                        StyledText {
                            visible: row.pull?.state === "error"
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: row.pull?.error ?? ""
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colError
                        }
                    }

                    // ---- Action
                    ColumnLayout {
                        Layout.alignment: Qt.AlignTop
                        spacing: 4

                        // Download / resume / retry
                        RippleButton {
                            id: downloadButton
                            readonly property bool canDownload: row.modelData.fit !== "no" && !row.noDiskSpace
                            visible: !row.installed && row.pull?.state !== "pulling" && row.pull?.state !== "queued"
                            opacity: canDownload ? 1 : 0.45  // stays enabled so the tooltip can explain why
                            Layout.alignment: Qt.AlignRight
                            implicitHeight: 32
                            implicitWidth: dlRow.implicitWidth + 18
                            topPadding: 0
                            bottomPadding: 0
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colPrimaryContainer
                            colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                            onClicked: if (canDownload) Ai.pullModel(row.modelData.id, row.modelData.sizeGb)
                            contentItem: RowLayout {
                                id: dlRow
                                spacing: 4
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: row.pull?.state === "error" ? "refresh" : "download"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.bottomMargin: 2
                                    text: row.pull?.state === "error" ? Translation.tr("Retry") : Translation.tr("Download")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnPrimaryContainer
                                }
                            }
                            StyledToolTip {
                                text: row.modelData.fit === "no"
                                    ? Translation.tr("Needs about %1 of memory with a %2k context: it does not fit in this PC").arg(root.formatGb(row.modelData.needGb)).arg(Ai.catalogCtx / 1024)
                                    : row.noDiskSpace ? Translation.tr("Not enough free space on the models disk")
                                    : row.modelData.fit === "cpu" ? Translation.tr("Will run on the CPU only: slow")
                                    : row.modelData.fit === "partial" ? Translation.tr("Does not fit in the GPU alone: part of it runs from RAM")
                                    : Translation.tr("Download %1 into %2").arg(row.modelData.id).arg(Ai.ollamaModelsDir)
                            }
                        }

                        // Queued / downloading: cancel
                        RippleButton {
                            visible: row.pull?.state === "pulling" || row.pull?.state === "queued"
                            Layout.alignment: Qt.AlignRight
                            implicitHeight: 32
                            implicitWidth: cancelRow.implicitWidth + 18
                            topPadding: 0
                            bottomPadding: 0
                            buttonRadius: Appearance.rounding.small
                            colBackground: Appearance.colors.colLayer3
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            onClicked: Ai.cancelPull(row.modelData.id)
                            contentItem: RowLayout {
                                id: cancelRow
                                spacing: 4
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "close"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnLayer3
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.bottomMargin: 2
                                    text: row.pull?.state === "queued" ? Translation.tr("Queued") : `${row.pull?.percent ?? 0}%`
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer3
                                }
                            }
                            StyledToolTip { text: Translation.tr("Cancel (the part already downloaded is kept)") }
                        }

                        // Installed: use now
                        RippleButton {
                            id: useButton
                            visible: row.installed
                            Layout.alignment: Qt.AlignRight
                            implicitHeight: 32
                            implicitWidth: useRow.implicitWidth + 18
                            topPadding: 0
                            bottomPadding: 0
                            buttonRadius: Appearance.rounding.small
                            toggled: Ai.getModel().model === row.modelData.id
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            enabled: !row.modelData.embedding
                            onClicked: {
                                Ai.setModel(Ai.safeModelName(row.modelData.id), false);
                                root.close();
                            }
                            contentItem: RowLayout {
                                id: useRow
                                spacing: 4
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: Ai.getModel().model === row.modelData.id ? "check_circle" : "check"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: useButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.bottomMargin: 2
                                    text: Ai.getModel().model === row.modelData.id ? Translation.tr("In use") : Translation.tr("Use now")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: useButton.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                            }
                            StyledToolTip { text: Translation.tr("Installed. Click to chat with it.") }
                        }
                    }
                }
            }
        }
    }
}
