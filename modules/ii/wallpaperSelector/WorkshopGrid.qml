import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * Wallpaper Engine Workshop grid.
 *  Online:  click opens the item in Steam so you can Subscribe; a downloaded item is set as wallpaper.
 *  Library: everything you are subscribed to, downloaded or not, with filters and delete.
 */
Item {
    id: root

    property int columns: 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    readonly property bool libraryMode: WorkshopWallpapers.libraryMode
    readonly property int count: grid.count

    property bool showRequirements: false
    property var pendingDelete: null   // { ids, title, bytes, single, includesCurrent }

    signal wallpaperApplied()

    Component.onCompleted: {
        WorkshopWallpapers.refreshLibraryInfo()
        WorkshopWallpapers.checkRequirements()
        if (WorkshopWallpapers.results.length === 0 && !WorkshopWallpapers.fetching) WorkshopWallpapers.refresh()
    }

    function moveSelection(delta) { grid.moveSelection(delta) }
    function activateCurrent() { grid.activateCurrent() }
    function toggleRequirements() {
        root.showRequirements = !root.showRequirements
        if (root.showRequirements) WorkshopWallpapers.checkRequirements()
    }

    function infoOf(item) {
        return root.libraryMode ? item : (WorkshopWallpapers.libraryInfo[item.id] ?? null)
    }

    function activate(item) {
        const info = root.infoOf(item)
        if (info && info.downloaded && info.file && info.file.length > 0) {
            Wallpapers.apply(info.file, root.useDarkMode)
            root.wallpaperApplied()
        } else if (info && info.downloaded) {
            WorkshopWallpapers.say(Translation.tr("Only video wallpapers can be used here (Scene and Web are not supported)"))
        } else {
            WorkshopWallpapers.subscribe(item)
        }
    }

    function askDelete(item) {
        const info = root.infoOf(item)
        if (!info || !info.downloaded || !info.dir || info.origin !== "workshop") return
        if (WorkshopWallpapers.isCurrentWallpaper(info)) {
            WorkshopWallpapers.say(Translation.tr("This is your current wallpaper, change it first"))
            return
        }
        root.pendingDelete = { ids: [item.id], title: item.title, bytes: info.size ?? 0, single: item, includesCurrent: false }
    }

    function askDeleteAll() {
        const all = WorkshopWallpapers.shown.filter(i => i.downloaded && i.dir && i.origin === "workshop")
        const ok = all.filter(i => !WorkshopWallpapers.isCurrentWallpaper(i))
        if (ok.length === 0) return
        root.pendingDelete = {
            ids: ok.map(i => i.id),
            title: "",
            bytes: ok.reduce((a, i) => a + (i.size || 0), 0),
            single: null,
            includesCurrent: ok.length < all.length
        }
    }

    function confirmDelete() {
        const d = root.pendingDelete
        root.pendingDelete = null
        if (d) WorkshopWallpapers.deleteItems(d.ids)
    }

    // ---------------------------------------------------------------- library header
    ColumnLayout {
        id: libraryHeader
        visible: root.libraryMode
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            leftMargin: 4
            rightMargin: 4
        }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { key: "all",         label: Translation.tr("All"),            count: WorkshopWallpapers.results.length },
                    { key: "downloaded",  label: Translation.tr("Downloaded"),     count: WorkshopWallpapers.downloadedItems.length },
                    { key: "pending",     label: Translation.tr("Not downloaded"), count: WorkshopWallpapers.pendingItems.length },
                    { key: "unsupported", label: Translation.tr("Unsupported"),    count: WorkshopWallpapers.unsupportedItems.length }
                ]
                delegate: RippleButton {
                    id: chip
                    required property var modelData
                    readonly property bool active: WorkshopWallpapers.libraryFilter === modelData.key
                    implicitHeight: 32
                    leftPadding: 14
                    rightPadding: 14
                    buttonRadius: height / 2
                    toggled: chip.active
                    colBackground: Appearance.colors.colLayer1
                    onClicked: WorkshopWallpapers.libraryFilter = modelData.key
                    contentItem: StyledText {
                        text: chip.modelData.label + "  " + chip.modelData.count
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: chip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: Translation.tr("%1 on disk").arg(WorkshopWallpapers.formatBytes(WorkshopWallpapers.downloadedBytes))
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                id: deleteAllBtn
                visible: WorkshopWallpapers.deletableItems.length > 0
                implicitHeight: 32
                leftPadding: 12
                rightPadding: 14
                buttonRadius: height / 2
                colBackground: Appearance.colors.colLayer1
                onClicked: root.askDeleteAll()
                contentItem: Row {
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "delete_sweep"
                        iconSize: 18
                        color: Appearance.m3colors.m3error
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Delete downloaded")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3error
                    }
                }
                StyledToolTip { text: Translation.tr("Delete the downloaded files of the wallpapers listed below") }
            }
        }

        // Where they come from: Steam Workshop or not
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            visible: WorkshopWallpapers.originList.filter(o => WorkshopWallpapers.countOrigin(o) > 0).length > 1

            StyledText {
                text: Translation.tr("Source")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                Layout.rightMargin: 2
            }

            Repeater {
                model: [
                    { key: "all",      label: Translation.tr("All"),                    count: WorkshopWallpapers.results.length },
                    { key: "workshop", label: Translation.tr("Steam Workshop"),         count: WorkshopWallpapers.countOrigin("workshop") },
                    { key: "mine",     label: Translation.tr("Made in Wallpaper Engine"), count: WorkshopWallpapers.countOrigin("mine") },
                    { key: "folder",   label: Translation.tr("My video folder"),        count: WorkshopWallpapers.countOrigin("folder") },
                    { key: "app",      label: Translation.tr("Built into Wallpaper Engine"), count: WorkshopWallpapers.countOrigin("app") }
                ].filter(c => c.key === "all" || c.count > 0)
                delegate: RippleButton {
                    id: originChip
                    required property var modelData
                    readonly property bool active: WorkshopWallpapers.originFilter === modelData.key
                    implicitHeight: 28
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: height / 2
                    toggled: originChip.active
                    colBackground: Appearance.colors.colLayer1
                    onClicked: WorkshopWallpapers.originFilter = modelData.key
                    contentItem: StyledText {
                        text: originChip.modelData.label + "  " + originChip.modelData.count
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: originChip.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
            Item { Layout.fillWidth: true }
        }

        StyledText {
            visible: text.length > 0
            Layout.leftMargin: 4
            text: WorkshopWallpapers.hiddenByRating > 0 && !WorkshopWallpapers.mature
                ? Translation.tr("%1 wallpaper(s) hidden by the mature filter").arg(WorkshopWallpapers.hiddenByRating)
                : ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    Item {
        id: content
        anchors {
            top: root.libraryMode ? libraryHeader.bottom : parent.top
            topMargin: root.libraryMode ? 6 : 0
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        // Loading
        ColumnLayout {
            anchors.centerIn: parent
            visible: WorkshopWallpapers.fetching && grid.count === 0
            spacing: 12
            MaterialLoadingIndicator {
                Layout.alignment: Qt.AlignHCenter
                colBg: Appearance.colors.colPrimary
            }
            StyledText {
                text: root.libraryMode ? Translation.tr("Reading your Wallpaper Engine library...") : Translation.tr("Searching the Steam Workshop...")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // Error
        ColumnLayout {
            anchors.centerIn: parent
            visible: WorkshopWallpapers.lastError.length > 0 && !WorkshopWallpapers.fetching
            spacing: 12
            MaterialSymbol {
                text: "cloud_off"
                iconSize: 48
                color: Appearance.m3colors.m3error
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: WorkshopWallpapers.lastError
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.maximumWidth: root.width * 0.8
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // Empty
        ColumnLayout {
            anchors.centerIn: parent
            visible: !WorkshopWallpapers.fetching && WorkshopWallpapers.lastError.length === 0 && grid.count === 0
            spacing: 12
            MaterialSymbol {
                text: root.libraryMode ? "folder_off" : "image_not_supported"
                iconSize: 48
                color: Appearance.colors.colSubtext
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: root.libraryMode
                    ? (WorkshopWallpapers.results.length === 0
                        ? Translation.tr("No Wallpaper Engine wallpapers found on this PC")
                        : Translation.tr("Nothing matches this filter"))
                    : Translation.tr("No results found")
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                visible: root.libraryMode && (Config.options.wallpaperSelector.liveWallpapersPath ?? "").length === 0
                text: Translation.tr("To list your own video files here, set a Live Wallpaper Folder in Settings > Interface.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.maximumWidth: root.width * 0.7
                horizontalAlignment: Text.AlignHCenter
            }
            StyledText {
                visible: root.libraryMode && WorkshopWallpapers.results.length === 0
                text: Translation.tr("Browse Online and click a wallpaper to subscribe in Steam. It shows up here once Steam finishes downloading it. The requirements button shows what is missing.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                Layout.alignment: Qt.AlignHCenter
                wrapMode: Text.WordWrap
                Layout.maximumWidth: root.width * 0.7
                horizontalAlignment: Text.AlignHCenter
            }
        }

        StyledGridView {
            id: grid
            anchors.fill: parent
            visible: count > 0
            focus: true

            property int currentSelection: -1
            property string pendingSelectionAfterPageChange: ""

            cellWidth: width / root.columns
            cellHeight: cellWidth / root.previewCellAspectRatio
            interactive: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: StyledScrollBar {}

            model: WorkshopWallpapers.shown

            function moveSelection(delta) {
                if (count === 0) return
                const newIndex = currentSelection + delta
                if (newIndex >= count) {
                    if (!root.libraryMode && !WorkshopWallpapers.fetching && WorkshopWallpapers.page < WorkshopWallpapers.totalPages) {
                        pendingSelectionAfterPageChange = "first"
                        WorkshopWallpapers.nextPage()
                    }
                    return
                }
                if (newIndex < 0) {
                    if (!root.libraryMode && !WorkshopWallpapers.fetching && WorkshopWallpapers.page > 1) {
                        pendingSelectionAfterPageChange = "last"
                        WorkshopWallpapers.previousPage()
                    }
                    return
                }
                currentSelection = newIndex
                positionViewAtIndex(currentSelection, GridView.Contain)
            }

            function currentItem_() {
                return (currentSelection >= 0 && currentSelection < count) ? WorkshopWallpapers.shown[currentSelection] : null
            }

            function activateCurrent() {
                const item = currentItem_()
                if (item) root.activate(item)
            }

            Connections {
                target: WorkshopWallpapers
                function onLoaded() {
                    if (grid.pendingSelectionAfterPageChange === "first") {
                        grid.currentSelection = 0
                        grid.positionViewAtBeginning()
                    } else if (grid.pendingSelectionAfterPageChange === "last") {
                        grid.currentSelection = grid.count - 1
                        grid.positionViewAtEnd()
                    } else {
                        grid.currentSelection = -1
                        grid.positionViewAtBeginning()
                    }
                    grid.pendingSelectionAfterPageChange = ""
                }
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Left) { moveSelection(-1); event.accepted = true }
                else if (event.key === Qt.Key_Right) { moveSelection(1); event.accepted = true }
                else if (event.key === Qt.Key_Up) { moveSelection(-root.columns); event.accepted = true }
                else if (event.key === Qt.Key_Down) { moveSelection(root.columns); event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activateCurrent(); event.accepted = true }
                else if (event.key === Qt.Key_Delete) {
                    const item = currentItem_()
                    if (item) root.askDelete(item)
                    event.accepted = true
                }
            }

            delegate: Item {
                id: cell
                required property var modelData
                required property int index

                width: grid.cellWidth
                height: grid.cellHeight

                readonly property var info: root.infoOf(modelData)
                readonly property string origin: modelData.origin ?? info?.origin ?? "workshop"
                readonly property bool downloaded: info?.downloaded ?? false
                readonly property bool subscribed: info?.subscribed ?? false
                readonly property bool supported: root.libraryMode ? modelData.supported : true
                readonly property bool adult: modelData.rating === "Mature" || modelData.rating === "Questionable"
                readonly property bool selected: index === grid.currentSelection
                readonly property bool isCurrent: downloaded && (cell.origin === "workshop" ? WorkshopWallpapers.isCurrentWallpaper(info) : (info?.file ?? "") === (Config.options.background.wallpaperPath ?? "x"))

                HoverHandler {
                    id: hover
                    onHoveredChanged: {
                        if (hovered) {
                            grid.currentSelection = cell.index
                            grid.forceActiveFocus()
                        } else if (grid.currentSelection === cell.index) {
                            grid.currentSelection = -1
                        }
                    }
                }

                Image {
                    id: thumb
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.wallpaperSelectorItemMargins
                    source: WorkshopWallpapers.previewSource(cell.modelData)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    opacity: cell.supported ? 1 : 0.45
                    sourceSize.width: grid.cellWidth
                    sourceSize.height: grid.cellHeight

                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: thumb.width
                            height: thumb.height
                            radius: Appearance.rounding.normal
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: cell.selected ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85) : "transparent"
                        border.width: cell.selected ? 2 : (cell.isCurrent ? 2 : 0)
                        border.color: cell.selected ? Appearance.colors.colPrimary : Appearance.colors.colTertiary
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2
                        visible: thumb.status !== Image.Ready
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: thumb.status === Image.Error ? "broken_image" : "image"
                            iconSize: 32
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                // Title strip
                Rectangle {
                    anchors {
                        left: thumb.left
                        right: thumb.right
                        bottom: thumb.bottom
                    }
                    height: titleText.implicitHeight + 10
                    color: ColorUtils.transparentize(Appearance.colors.colScrim, 0.25)
                    opacity: cell.selected ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }
                    bottomLeftRadius: Appearance.rounding.normal
                    bottomRightRadius: Appearance.rounding.normal
                    StyledText {
                        id: titleText
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 8
                        }
                        text: cell.modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: "white"
                    }
                }

                // Badges, top left: age rating, type (when not a video), update
                Row {
                    anchors {
                        top: thumb.top
                        left: thumb.left
                        margins: 8
                    }
                    spacing: 4
                    Rectangle {
                        visible: cell.adult
                        radius: Appearance.rounding.small
                        color: Appearance.m3colors.m3error
                        implicitWidth: adultText.implicitWidth + 10
                        implicitHeight: adultText.implicitHeight + 4
                        StyledText {
                            id: adultText
                            anchors.centerIn: parent
                            text: cell.modelData.rating === "Mature" ? "18+" : "16+"
                            font.pixelSize: Appearance.font.pixelSize.smaller * 0.9
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onError
                        }
                    }
                    Rectangle {
                        visible: root.libraryMode && !cell.supported
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colScrim
                        implicitWidth: typeText.implicitWidth + 10
                        implicitHeight: typeText.implicitHeight + 4
                        StyledText {
                            id: typeText
                            anchors.centerIn: parent
                            text: {
                                const t = cell.modelData.type ?? ""
                                return t.length > 0 && t !== "unknown" ? t.charAt(0).toUpperCase() + t.slice(1) : Translation.tr("Unsupported")
                            }
                            font.pixelSize: Appearance.font.pixelSize.smaller * 0.9
                            color: "white"
                        }
                    }
                    Rectangle {
                        visible: root.libraryMode && cell.origin !== "workshop"
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colTertiaryContainer
                        implicitWidth: originText.implicitWidth + 10
                        implicitHeight: originText.implicitHeight + 4
                        StyledText {
                            id: originText
                            anchors.centerIn: parent
                            text: cell.origin === "folder" ? Translation.tr("My video")
                                : (cell.origin === "mine" ? Translation.tr("Made in WE") : Translation.tr("Built into WE"))
                            font.pixelSize: Appearance.font.pixelSize.smaller * 0.9
                            color: Appearance.colors.colOnTertiaryContainer
                        }
                    }
                    Rectangle {
                        visible: root.libraryMode && cell.downloaded && (cell.modelData.needsUpdate ?? false)
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colSecondaryContainer
                        implicitWidth: updText.implicitWidth + 10
                        implicitHeight: updText.implicitHeight + 4
                        StyledText {
                            id: updText
                            anchors.centerIn: parent
                            text: Translation.tr("Update")
                            font.pixelSize: Appearance.font.pixelSize.smaller * 0.9
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }

                // Status, top right: downloaded / subscribed but not downloaded
                Rectangle {
                    anchors {
                        top: thumb.top
                        right: thumb.right
                        margins: 8
                    }
                    visible: (cell.downloaded || cell.subscribed) && cell.origin === "workshop"
                    radius: Appearance.rounding.small
                    color: cell.downloaded ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    implicitWidth: statusRow.implicitWidth + 10
                    implicitHeight: statusRow.implicitHeight + 4
                    Row {
                        id: statusRow
                        anchors.centerIn: parent
                        spacing: 2
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: cell.isCurrent ? "wallpaper" : (cell.downloaded ? "download_done" : "cloud_download")
                            iconSize: 13
                            color: cell.downloaded ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: cell.isCurrent ? Translation.tr("In use")
                                : (cell.downloaded ? Translation.tr("Downloaded") : Translation.tr("Subscribed, not downloaded"))
                            font.pixelSize: Appearance.font.pixelSize.smaller * 0.9
                            color: cell.downloaded ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }

                // Resolution / size, bottom left (hidden while the title strip shows)
                Rectangle {
                    anchors {
                        bottom: thumb.bottom
                        left: thumb.left
                        margins: 8
                    }
                    readonly property string label: {
                        const parts = []
                        if (cell.modelData.resolution) parts.push(cell.modelData.resolution)
                        if (root.libraryMode && (cell.modelData.size ?? 0) > 0) parts.push(WorkshopWallpapers.formatBytes(cell.modelData.size))
                        return parts.join("  ·  ")
                    }
                    visible: label.length > 0 && !cell.selected
                    color: Appearance.colors.colScrim
                    radius: Appearance.rounding.small
                    implicitWidth: resText.implicitWidth + 8
                    implicitHeight: resText.implicitHeight + 4
                    StyledText {
                        id: resText
                        anchors.centerIn: parent
                        text: parent.label
                        font.pixelSize: Appearance.font.pixelSize.smaller * 0.85
                        color: "white"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        grid.currentSelection = cell.index
                        root.activate(cell.modelData)
                    }
                }

                // Hover actions (above the click area)
                Row {
                    anchors {
                        top: thumb.top
                        right: thumb.right
                        topMargin: ((cell.downloaded || cell.subscribed) && cell.origin === "workshop") ? 34 : 8
                        rightMargin: 8
                    }
                    spacing: 4
                    z: 10
                    opacity: hover.hovered && cell.origin === "workshop" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: 100 } }

                    Repeater {
                        model: {
                            const a = [{ icon: "open_in_new", tip: Translation.tr("Open the Workshop page (to unsubscribe, rate...)"), act: "page" }]
                            if (!cell.downloaded)
                                a.push({ icon: cell.subscribed ? "cloud_download" : "add_circle", tip: cell.subscribed ? Translation.tr("Open in Steam to download") : Translation.tr("Subscribe in Steam"), act: "sub" })
                            else
                                a.push({ icon: "delete", tip: cell.isCurrent ? Translation.tr("Current wallpaper, change it first") : Translation.tr("Delete the downloaded files"), act: "delete" })
                            return a
                        }
                        delegate: Rectangle {
                            id: actionBtn
                            required property var modelData
                            width: 26
                            height: 26
                            radius: 13
                            color: modelData.act === "delete" && !cell.isCurrent ? Appearance.m3colors.m3error : Appearance.colors.colScrim
                            opacity: modelData.act === "delete" && cell.isCurrent ? 0.5 : 1
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: actionBtn.modelData.icon
                                iconSize: 15
                                color: actionBtn.modelData.act === "delete" && !cell.isCurrent ? Appearance.m3colors.m3onError : "white"
                            }
                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (actionBtn.modelData.act === "page") WorkshopWallpapers.openInBrowser(cell.modelData)
                                    else if (actionBtn.modelData.act === "sub") WorkshopWallpapers.subscribe(cell.modelData)
                                    else root.askDelete(cell.modelData)
                                }
                                StyledToolTip {
                                    visible: actionMouse.containsMouse
                                    text: actionBtn.modelData.tip
                                }
                            }
                        }
                    }
                }
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: grid.width
                    height: grid.height
                    radius: Appearance.rounding.normal
                }
            }
        }
    }

    // ---------------------------------------------------------------- message toast
    Rectangle {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 16
        }
        z: 50
        visible: opacity > 0
        opacity: WorkshopWallpapers.notice.length > 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        radius: Appearance.rounding.full
        color: Appearance.colors.colSecondaryContainer
        implicitWidth: noticeText.implicitWidth + 32
        implicitHeight: noticeText.implicitHeight + 16
        StyledText {
            id: noticeText
            anchors.centerIn: parent
            text: WorkshopWallpapers.notice
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    // ---------------------------------------------------------------- requirements
    Rectangle {
        id: requirementsOverlay
        anchors.fill: parent
        z: 100
        visible: root.showRequirements
        color: ColorUtils.transparentize(Appearance.colors.colScrim, 0.35)
        radius: Appearance.rounding.normal

        MouseArea { // click outside closes
            anchors.fill: parent
            onClicked: root.showRequirements = false
        }

        Rectangle {
            id: reqCard
            anchors.centerIn: parent
            width: Math.min(620, parent.width - 48)
            implicitHeight: reqColumn.implicitHeight + 32
            height: Math.min(implicitHeight, parent.height - 32)
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1Base // opaque: readable even with transparency on
            clip: true

            MouseArea { anchors.fill: parent } // swallow clicks on the card

            ColumnLayout {
                id: reqColumn
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    MaterialSymbol {
                        text: WorkshopWallpapers.requiredFailing > 0 ? "warning" : "fact_check"
                        iconSize: 24
                        color: WorkshopWallpapers.requiredFailing > 0 ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Requirements")
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 16
                        onClicked: WorkshopWallpapers.checkRequirements()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledToolTip { text: Translation.tr("Check again") }
                    }
                    RippleButton {
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 16
                        onClicked: root.showRequirements = false
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            text: "close"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: WorkshopWallpapers.requirementsLoaded
                        ? (WorkshopWallpapers.requiredFailing > 0
                            ? Translation.tr("%1 required item(s) missing. Without them some features will not work.").arg(WorkshopWallpapers.requiredFailing)
                            : Translation.tr("Everything required is in place."))
                        : Translation.tr("Checking...")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                Repeater {
                    model: WorkshopWallpapers.requirements
                    delegate: RowLayout {
                        id: reqRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 10
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignTop
                            text: reqRow.modelData.ok ? "check_circle" : (reqRow.modelData.level === "required" ? "cancel" : "error")
                            iconSize: 22
                            color: reqRow.modelData.ok ? Appearance.colors.colPrimary
                                : (reqRow.modelData.level === "required" ? Appearance.m3colors.m3error : Appearance.colors.colTertiary)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: reqRow.modelData.label + (reqRow.modelData.level === "required" ? "" : "  (" + Translation.tr("recommended") + ")")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                wrapMode: Text.WordWrap
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: !reqRow.modelData.ok
                                text: reqRow.modelData.hint
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Only video wallpapers (mp4/webm...) can be applied. Scene, Web and Application ones are listed in the Library, dimmed, but cannot be used here.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    // ---------------------------------------------------------------- delete confirmation
    Rectangle {
        id: deleteOverlay
        anchors.fill: parent
        z: 110
        visible: root.pendingDelete !== null
        color: ColorUtils.transparentize(Appearance.colors.colScrim, 0.35)
        radius: Appearance.rounding.normal

        MouseArea { // click outside cancels
            anchors.fill: parent
            onClicked: root.pendingDelete = null
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(520, parent.width - 48)
            implicitHeight: delColumn.implicitHeight + 32
            height: implicitHeight
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1Base

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: delColumn
                anchors {
                    fill: parent
                    margins: 16
                }
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        text: "delete"
                        iconSize: 24
                        color: Appearance.m3colors.m3error
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: root.pendingDelete
                            ? (root.pendingDelete.single
                                ? Translation.tr("Delete \"%1\"?").arg(root.pendingDelete.title)
                                : Translation.tr("Delete %1 downloaded wallpapers?").arg(root.pendingDelete.ids.length))
                            : ""
                        font.pixelSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("This removes the downloaded files from this PC and frees %1. It does not unsubscribe you: while you stay subscribed, Steam may download it again.").arg(WorkshopWallpapers.formatBytes(root.pendingDelete?.bytes ?? 0))
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.pendingDelete?.includesCurrent ?? false
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Your current wallpaper is not included.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        visible: root.pendingDelete?.single ?? false
                        implicitHeight: 36
                        leftPadding: 14
                        rightPadding: 14
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colLayer2
                        onClicked: if (root.pendingDelete?.single) WorkshopWallpapers.openInBrowser(root.pendingDelete.single)
                        contentItem: StyledText {
                            text: Translation.tr("Open page to unsubscribe")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RippleButton {
                        implicitHeight: 36
                        leftPadding: 16
                        rightPadding: 16
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colLayer2
                        onClicked: root.pendingDelete = null
                        contentItem: StyledText {
                            text: Translation.tr("Cancel")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                    RippleButton {
                        implicitHeight: 36
                        leftPadding: 16
                        rightPadding: 16
                        buttonRadius: height / 2
                        colBackground: Appearance.m3colors.m3error
                        colBackgroundHover: Appearance.m3colors.m3error
                        onClicked: root.confirmDelete()
                        contentItem: StyledText {
                            text: Translation.tr("Delete")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3onError
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
        }
    }
}
