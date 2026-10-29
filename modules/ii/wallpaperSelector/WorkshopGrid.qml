import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * Wallpaper Engine Workshop grid. Online: click opens the item in Steam so you can
 * Subscribe; Installed (or already downloaded): click sets it as the wallpaper.
 */
Item {
    id: root

    property int columns: 4
    property real previewCellAspectRatio: 4 / 3
    property bool useDarkMode: Appearance.m3colors.darkmode
    readonly property bool installedMode: WorkshopWallpapers.mode === "installed"
    readonly property int count: grid.count

    signal wallpaperApplied()

    Component.onCompleted: {
        WorkshopWallpapers.refreshInstalled()
        if (WorkshopWallpapers.results.length === 0 && !WorkshopWallpapers.fetching) WorkshopWallpapers.refresh()
    }

    function moveSelection(delta) { grid.moveSelection(delta) }
    function activateCurrent() { grid.activateCurrent() }

    function localPathOf(item) {
        return item.file ?? WorkshopWallpapers.installedIds[item.id] ?? ""
    }

    function activate(item) {
        const path = root.localPathOf(item)
        if (path.length > 0) {
            Wallpapers.apply(path, root.useDarkMode)
            root.wallpaperApplied()
        } else {
            WorkshopWallpapers.subscribe(item)
        }
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
            text: root.installedMode ? Translation.tr("Reading downloaded wallpapers...") : Translation.tr("Searching the Steam Workshop...")
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
            text: root.installedMode ? "folder_off" : "image_not_supported"
            iconSize: 48
            color: Appearance.colors.colSubtext
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            text: root.installedMode ? Translation.tr("No downloaded Workshop video wallpapers yet") : Translation.tr("No results found")
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.small
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            visible: root.installedMode
            text: Translation.tr("Browse Online and click a wallpaper to subscribe in Steam. It shows up here once Steam finishes downloading it.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            Layout.alignment: Qt.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: root.width * 0.7
            horizontalAlignment: Text.AlignHCenter
        }
        StyledText {
            visible: root.installedMode && !WorkshopWallpapers.mature && ((WorkshopWallpapers.skipped.rating ?? 0) > 0)
            text: Translation.tr("%1 downloaded wallpaper(s) are hidden by the mature filter").arg(WorkshopWallpapers.skipped.rating ?? 0)
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            visible: root.installedMode && (((WorkshopWallpapers.skipped.scene ?? 0) + (WorkshopWallpapers.skipped.web ?? 0) + (WorkshopWallpapers.skipped.application ?? 0)) > 0)
            text: Translation.tr("Scene, Web and Application wallpapers are not supported here, only videos")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            Layout.alignment: Qt.AlignHCenter
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

        model: WorkshopWallpapers.results

        function moveSelection(delta) {
            if (count === 0) return
            const newIndex = currentSelection + delta
            if (newIndex >= count) {
                if (!WorkshopWallpapers.fetching && WorkshopWallpapers.page < WorkshopWallpapers.totalPages) {
                    pendingSelectionAfterPageChange = "first"
                    WorkshopWallpapers.nextPage()
                }
                return
            }
            if (newIndex < 0) {
                if (!WorkshopWallpapers.fetching && WorkshopWallpapers.page > 1) {
                    pendingSelectionAfterPageChange = "last"
                    WorkshopWallpapers.previousPage()
                }
                return
            }
            currentSelection = newIndex
            positionViewAtIndex(currentSelection, GridView.Contain)
        }

        function activateCurrent() {
            if (currentSelection >= 0 && currentSelection < count) {
                const item = WorkshopWallpapers.results[currentSelection]
                if (item) root.activate(item)
            }
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
        }

        delegate: Item {
            id: cell
            required property var modelData
            required property int index

            width: grid.cellWidth
            height: grid.cellHeight

            readonly property string localPath: root.localPathOf(modelData)
            readonly property bool downloaded: localPath.length > 0
            readonly property bool adult: modelData.rating === "Mature" || modelData.rating === "Questionable"
            readonly property bool selected: index === grid.currentSelection

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
                    border.width: cell.selected ? 2 : 0
                    border.color: Appearance.colors.colPrimary
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

            // Badges, top row: rating on the left, status on the right
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
            }
            Rectangle {
                anchors {
                    top: thumb.top
                    right: thumb.right
                    margins: 8
                }
                visible: cell.downloaded
                radius: Appearance.rounding.small
                color: Appearance.colors.colPrimary
                implicitWidth: dlRow.implicitWidth + 10
                implicitHeight: dlRow.implicitHeight + 4
                Row {
                    id: dlRow
                    anchors.centerIn: parent
                    spacing: 2
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "download_done"
                        iconSize: 13
                        color: Appearance.colors.colOnPrimary
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Downloaded")
                        font.pixelSize: Appearance.font.pixelSize.smaller * 0.9
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }

            // Resolution, bottom left (hidden while the title strip shows)
            Rectangle {
                anchors {
                    bottom: thumb.bottom
                    left: thumb.left
                    margins: 8
                }
                visible: !!cell.modelData.resolution && !cell.selected
                color: Appearance.colors.colScrim
                radius: Appearance.rounding.small
                implicitWidth: resText.implicitWidth + 8
                implicitHeight: resText.implicitHeight + 4
                StyledText {
                    id: resText
                    anchors.centerIn: parent
                    text: cell.modelData.resolution ?? ""
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
                    topMargin: cell.downloaded ? 34 : 8
                    rightMargin: 8
                }
                spacing: 4
                z: 10
                opacity: hover.hovered ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 100 } }

                Repeater {
                    model: [
                        { icon: "open_in_new", tip: Translation.tr("Open the Workshop page"), act: "page", needsOnline: true },
                        { icon: "add_circle", tip: Translation.tr("Subscribe in Steam"), act: "sub", needsOnline: true }
                    ]
                    delegate: Rectangle {
                        id: actionBtn
                        required property var modelData
                        visible: !cell.downloaded || modelData.act === "page"
                        width: 26
                        height: 26
                        radius: 13
                        color: Appearance.colors.colScrim
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: actionBtn.modelData.icon
                            iconSize: 15
                            color: "white"
                        }
                        MouseArea {
                            id: actionMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (actionBtn.modelData.act === "page") WorkshopWallpapers.openInBrowser(cell.modelData)
                                else WorkshopWallpapers.subscribe(cell.modelData)
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
