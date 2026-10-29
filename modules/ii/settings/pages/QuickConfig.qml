import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

ContentPage {
    id: page
    property bool isMinimal: Config.options.settings.style === "minimal"
    forceWidth: true
    baseWidth: !isMinimal ? 720 : 600
    bottomContentPadding: 35

    // Papirus folder colors (same list as scripts/theming/papirus-folder-color.py)
    readonly property var papirusColors: [
        { id: "adwaita", name: "Adwaita" }, { id: "black", name: "Black" }, { id: "blue", name: "Blue" },
        { id: "bluegrey", name: "Blue grey" }, { id: "breeze", name: "Breeze" }, { id: "brown", name: "Brown" },
        { id: "carmine", name: "Carmine" }, { id: "cyan", name: "Cyan" }, { id: "darkcyan", name: "Dark cyan" },
        { id: "deeporange", name: "Deep orange" }, { id: "green", name: "Green" }, { id: "grey", name: "Grey" },
        { id: "indigo", name: "Indigo" }, { id: "magenta", name: "Magenta" }, { id: "nordic", name: "Nordic" },
        { id: "orange", name: "Orange" }, { id: "palebrown", name: "Pale brown" }, { id: "paleorange", name: "Pale orange" },
        { id: "pink", name: "Pink" }, { id: "red", name: "Red" }, { id: "teal", name: "Teal" },
        { id: "violet", name: "Violet" }, { id: "white", name: "White" }, { id: "yellow", name: "Yellow" },
        { id: "yaru", name: "Yaru" }
    ]
    readonly property var folderTheming: Config.options.appearance.wallpaperTheming
    readonly property string folderSelected: folderTheming.papirusFolderChoice !== ""
        ? folderTheming.papirusFolderChoice
        : (folderTheming.papirusFolderColor ? "auto" : "default")

    function pickFolderColor(key) {
        let args;
        if (key === "auto") {
            folderTheming.papirusFolderChoice = "";
            folderTheming.papirusFolderColor = true;
            args = ["--apply"];
        } else if (key === "default") {
            folderTheming.papirusFolderChoice = "";
            folderTheming.papirusFolderColor = false;
            args = ["--restore"];
        } else {
            folderTheming.papirusFolderChoice = key;
            folderTheming.papirusFolderColor = false;
            args = ["--apply", "--folder", key];
        }
        Quickshell.execDetached(["python3", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/theming/papirus-folder-color.py`].concat(args));
    }

    component SmallLightDarkPreferenceButton: RippleButton {
        id: smallLightDarkPreferenceButton
        required property bool dark
        property color colText: toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        padding: 5
        Layout.fillWidth: true
        Layout.fillHeight: true
        toggled: Appearance.m3colors.darkmode === dark
        colBackground: Appearance.colors.colLayer2
        onClicked: {
            Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${dark ? "dark" : "light"} --noswitch`]);
        }
        contentItem: Item {
            anchors.centerIn: parent
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 30
                    text: dark ? "dark_mode" : "light_mode"
                    color: smallLightDarkPreferenceButton.colText
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: dark ? Translation.tr("Dark") : Translation.tr("Light")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: smallLightDarkPreferenceButton.colText
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 16

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Wallpaper & Colors")
            shape: MaterialShape.Shape.Puffy
            Layout.fillWidth: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                Rectangle {
                    Layout.preferredWidth: isMinimal ? 600 : 420 
                    Layout.preferredHeight: isMinimal ? 400 : 280 
                    radius: Appearance.rounding.large - 3
                    color: Appearance.colors.colLayer2
                    clip: true

                    StyledImage {
                        anchors.fill: parent
                        sourceSize.width: isMinimal ? 600 : 420
                        sourceSize.height: isMinimal ? 400 : 280
                        fillMode: Image.PreserveAspectCrop
                        source: /\.(mp4|webm|mkv|avi|mov)$/i.test(Config.options.background.wallpaperPath)
                            ? Config.options.background.thumbnailPath
                            : Config.options.background.wallpaperPath
                        cache: false
                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: isMinimal ? 600 : 420; height: isMinimal ? 400 : 280
                                radius: Appearance.rounding.large - 3
                            }
                        }
                    }

                    ToolbarPairedFab {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 8
                        iconText: "colorize"
                        onClicked: {
                            Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color"]);
                        }
                        StyledToolTip {
                            text: "Change accent color"
                        }
                    }
                }

                ColumnLayout {
                    visible: !isMinimal
                    Layout.fillWidth: true
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 2
                        uniformCellSizes: true
                        SmallLightDarkPreferenceButton { dark: false }
                        SmallLightDarkPreferenceButton { dark: true }
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        rowSpacing: 2
                        columnSpacing: 2

                        Repeater {
                            model: [
                                { value: "auto",               displayName: Translation.tr("Auto"),        icon: "auto_awesome" },
                                { value: "scheme-content",     displayName: Translation.tr("Content"),     icon: "image" },
                                { value: "scheme-expressive",  displayName: Translation.tr("Expressive"),  icon: "palette" },
                                { value: "scheme-fidelity",    displayName: Translation.tr("Fidelity"),    icon: "equal" },
                                { value: "scheme-fruit-salad", displayName: Translation.tr("Fruit Salad"), icon: "nutrition" },
                                { value: "scheme-monochrome",  displayName: Translation.tr("Monochrome"),  icon: "invert_colors" },
                                { value: "scheme-neutral",     displayName: Translation.tr("Neutral"),     icon: "tonality" },
                                { value: "scheme-rainbow",     displayName: Translation.tr("Rainbow"),     icon: "gradient" },
                                { value: "scheme-tonal-spot",  displayName: Translation.tr("Tonal Spot"),  icon: "lens" },
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: width * 0.6
                                radius: Appearance.rounding.normal

                                property bool isSelected: Config.options.appearance.palette.type === modelData.value
                                property bool hovered: hoverArea.containsMouse

                                color: isSelected ? Appearance.colors.colPrimary 
                                    : hovered ? Appearance.colors.colSecondaryContainerHover 
                                    : Appearance.colors.colSecondaryContainer

                                MaterialSymbol {
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.margins: 8
                                    text: modelData.icon
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: parent.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                }

                                StyledText {
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.margins: 8
                                    text: modelData.displayName
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: parent.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                                }

                                MouseArea {
                                    id: hoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Config.options.appearance.palette.type = modelData.value
                                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`])
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ConfigRow {
                ConfigSwitch {
                    buttonIcon: "motion_mode"
                    text: Translation.tr("Transparency")
                    checked: Config.options.appearance.transparency.enable
                    onCheckedChanged: { Config.options.appearance.transparency.enable = checked; }
                }
                ConfigSwitch {
                    buttonIcon: "autofps_select"
                    enabled: Config.options.appearance.transparency.enable
                    text: Translation.tr("Automatic")
                    checked: Config.options.appearance.transparency.automatic
                    onCheckedChanged: { Config.options.appearance.transparency.automatic = checked; }
                }
            }
        }

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Bar & Screen")
            shape: MaterialShape.Shape.ClamShell
            Layout.fillWidth: true
            collapsible: false

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: 8
                columnSpacing: 8
                uniformCellWidths: true

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: barPosCol.implicitHeight + 24
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: "transparent"

                    ColumnLayout {
                        id: barPosCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "swap_vert"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Bar position")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: barPosArray
                            Layout.fillWidth: true
                            currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                            onSelected: newValue => {
                                Config.options.bar.bottom = (newValue & 1) !== 0;
                                Config.options.bar.vertical = (newValue & 2) !== 0;
                            }
                            options: [
                                { displayName: Translation.tr("Top"), icon: "arrow_upward",   value: 0 },
                                { displayName: Translation.tr("Left"), icon: "arrow_back",     value: 2 },
                                { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                                { displayName: Translation.tr("Right"), icon: "arrow_forward",  value: 3 }
                            ]
                        }

                        Item { Layout.fillHeight: true } // keeps the content at the top when a neighbor card is taller
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: barStyleCol.implicitHeight + 24
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: 1
                    border.color: "transparent"

                    ColumnLayout {
                        id: barStyleCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "settop_component"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Bar style")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: barStyleArray
                            Layout.fillWidth: true
                            currentValue: Config.options.bar.cornerStyle
                            onSelected: newValue => { Config.options.bar.cornerStyle = newValue; }
                            options: [
                                { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                                { displayName: Translation.tr("Split Hug"), icon: "splitscreen", value: 6 },
                                { displayName: Translation.tr("Float"), icon: "view_day",   value: 1 },
                                { displayName: Translation.tr("Islands"), icon: "crop_3_2",   value: 2 },
                                { displayName: Translation.tr("M3"), icon: "interests",  value: 3 },
                                { displayName: Translation.tr("M3 Hug"), icon: "category", value: 4 },
                                { displayName: Translation.tr("Panel"), icon: "toolbar", value: 5 }
                            ]
                        }

                        Item { Layout.fillHeight: true } // keeps the content at the top when a neighbor card is taller
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: groupStyleCol.implicitHeight + 24
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    ColumnLayout {
                        id: groupStyleCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "tab_group"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Group style")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: groupStyleArray
                            Layout.fillWidth: true
                            currentValue: Config.options.bar.borderless
                            onSelected: newValue => { Config.options.bar.borderless = newValue; }
                            options: [
                                { displayName: Translation.tr("None"),      icon: "block",         value: "transparent" },
                                { displayName: Translation.tr("Pills"),     icon: "pill",          value: "pills" },
                                { displayName: Translation.tr("Separated"), icon: "view_column_2", value: "separated" },
                                { displayName: Translation.tr("Segmented"), icon: "tablet",        value: "segmented" }
                            ]
                        }

                        Item { Layout.fillHeight: true } // keeps the content at the top when a neighbor card is taller
                    }
                    
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: screenRoundCol.implicitHeight + 24
                    Layout.fillHeight: true
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1

                    ColumnLayout {
                        id: screenRoundCol
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: "rounded_corner"
                                iconSize: Appearance.font.pixelSize.normal + 4
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: Translation.tr("Screen round corner")
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                                font.weight: Font.Medium
                            }
                        }

                        ConfigSelectionArray {
                            id: screenRoundArray
                            Layout.fillWidth: true
                            currentValue: Config.options.appearance.fakeScreenRounding
                            onSelected: newValue => { Config.options.appearance.fakeScreenRounding = newValue; }
                            options: [
                                { displayName: Translation.tr("No"),                  icon: "close",           value: 0 },
                                { displayName: Translation.tr("Yes"),                 icon: "check",           value: 1 },
                                { displayName: Translation.tr("When not fullscreen"), icon: "fullscreen_exit", value: 2 }
                            ]
                        }

                        Item { Layout.fillHeight: true } // keeps the content at the top when a neighbor card is taller
                    }
                }
            }
        }

        ContentSection {
            icon: "folder"
            title: Translation.tr("Papirus folder color")
            shape: MaterialShape.Shape.Cookie6Sided
            Layout.fillWidth: true
            collapsible: false
            visible: SystemAppearance.iconThemes.some(t => t.startsWith("Papirus"))

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: page.folderSelected === "auto"
                    ? Translation.tr("Auto: the folders follow the wallpaper color.")
                    : page.folderSelected === "default"
                        ? Translation.tr("Default: the folder color set by the Papirus theme itself.")
                        : Translation.tr("Fixed color. It stays when you change the wallpaper.")
            }
            StyledText {
                Layout.fillWidth: true
                visible: SystemAppearance.iconTheme !== "" && !/^Papirus/.test(SystemAppearance.iconTheme)
                wrapMode: Text.WordWrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colError
                text: Translation.tr("The active icon theme is not Papirus. The color applies once you pick Papirus in Settings > General.")
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [
                        { id: "default", name: Translation.tr("Default") },
                        { id: "auto", name: Translation.tr("Auto") }
                    ].concat(page.papirusColors.map(c => ({ id: c.id, name: Translation.tr(c.name) })))

                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        readonly property bool isSelected: page.folderSelected === modelData.id
                        width: 84
                        height: 84
                        radius: Appearance.rounding.normal
                        color: isSelected ? Appearance.colors.colPrimary
                            : tileMouse.containsMouse ? Appearance.colors.colSecondaryContainerHover
                            : Appearance.colors.colSecondaryContainer

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 2

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: 44
                                implicitHeight: 44

                                Image {
                                    anchors.fill: parent
                                    visible: tile.modelData.id !== "auto"
                                    sourceSize: Qt.size(88, 88)
                                    smooth: true
                                    source: "file:///usr/share/icons/Papirus-Dark/64x64/places/"
                                        + (tile.modelData.id === "default" ? "folder.svg" : "folder-" + tile.modelData.id + ".svg")
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: tile.modelData.id === "auto"
                                    text: "auto_awesome"
                                    iconSize: 34
                                    color: tile.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: tile.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                                color: tile.isSelected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                            }
                        }

                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.pickFolderColor(tile.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
