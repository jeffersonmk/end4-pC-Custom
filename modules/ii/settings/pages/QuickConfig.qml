import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models

ContentPage {
    id: page
    property bool isMinimal: Config.options.settings.style === "minimal"
    forceWidth: true
    baseWidth: !isMinimal ? 700 : 600
    bottomContentPadding: 35

    // Label above a row of inline options (the buttons wrap onto more lines when narrow).
    component OptionRow: ColumnLayout {
        id: optionRow
        property string label: ""
        property alias options: selection.options
        property alias currentValue: selection.currentValue
        signal selected(var newValue)
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            Layout.leftMargin: 2
            text: optionRow.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        ConfigSelectionArray {
            id: selection
            Layout.fillWidth: true
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            onSelected: newValue => optionRow.selected(newValue)
        }
    }

    // Miniature of the user's screen. It reads the same options the controls below write, so
    // every change shows up here immediately. Shapes are an approximation, not a screenshot.
    component ScreenPreview: ClippingRectangle {
        id: pv

        readonly property bool vertical: Config.options.bar.vertical
        readonly property bool atEnd: Config.options.bar.bottom
        readonly property int barStyle: Config.options.bar.cornerStyle
        readonly property string groupStyle: Config.options.bar.borderless
        readonly property bool barHasBg: Config.options.bar.showBackground
        readonly property bool frameOn: Config.options.bar.showFrame
        readonly property color frameCol: Appearance.getColorFromName(Config.options.bar.frameColor)
        readonly property real frameW: Math.max(3, Config.options.bar.frameThickness * 1.3)
        readonly property bool attached: [0, 4, 5, 6].includes(barStyle)
        readonly property bool islands: barStyle === 2
        readonly property bool splitGroups: barStyle === 4 || barStyle === 6
        readonly property real barThick: barStyle === 5 ? 20 : 16
        readonly property real gapAlong: attached ? 0 : 7
        readonly property real gapAcross: attached ? 0 : 5
        readonly property string barSide: vertical ? (atEnd ? "right" : "left") : (atEnd ? "bottom" : "top")
        readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0

        function frameVisible(side) {
            if (!frameOn) return false;
            if (barStyle === 0 && side === barSide) return centerOnly || !barHasBg;
            return true;
        }
        readonly property real fL: frameVisible("left") ? frameW : 0
        readonly property real fR: frameVisible("right") ? frameW : 0
        readonly property real fT: frameVisible("top") ? frameW : 0
        readonly property real fB: frameVisible("bottom") ? frameW : 0
        readonly property real barSpace: barThick + gapAcross * 2

        radius: Appearance.rounding.large - 3
        color: Appearance.colors.colLayer2

        StyledImage {
            anchors.fill: parent
            sourceSize.height: 720
            fillMode: Image.PreserveAspectCrop
            cache: false
            source: /\.(mp4|webm|mkv|avi|mov)$/i.test(Config.options.background.wallpaperPath)
                ? Config.options.background.thumbnailPath
                : Config.options.background.wallpaperPath
        }

        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.22 }

        // Two fake windows, painted with the live palette so scheme/mode changes are visible.
        Item {
            id: desk
            anchors {
                fill: parent
                leftMargin: pv.fL + (pv.barSide === "left" ? pv.barSpace : 0) + 10
                rightMargin: pv.fR + (pv.barSide === "right" ? pv.barSpace : 0) + 10
                topMargin: pv.fT + (pv.barSide === "top" ? pv.barSpace : 0) + 10
                bottomMargin: pv.fB + (pv.barSide === "bottom" ? pv.barSpace : 0) + 10
            }

            Rectangle {
                x: 0; y: 0
                width: parent.width * 0.58
                height: parent.height * 0.72
                radius: 7
                color: Appearance.colors.colLayer1Base
                Rectangle { x: 0; y: 0; width: parent.width; height: 12; radius: 7; color: Appearance.colors.colLayer2Base }
                Rectangle { x: 10; y: 24; width: parent.width * 0.5; height: 6; radius: 3; color: Appearance.colors.colOnLayer1; opacity: 0.55 }
                Rectangle { x: 10; y: 36; width: parent.width * 0.35; height: 6; radius: 3; color: Appearance.colors.colSubtext; opacity: 0.5 }
                Rectangle { x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 10; width: 38; height: 14; radius: 7; color: Appearance.colors.colPrimary }
            }
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: parent.width * 0.5
                height: parent.height * 0.62
                radius: 7
                color: Appearance.colors.colSecondaryContainer
                Rectangle { x: 10; y: 12; width: 16; height: 16; radius: 8; color: Appearance.colors.colTertiary }
                Rectangle { x: 34; y: 15; width: parent.width * 0.4; height: 6; radius: 3; color: Appearance.colors.colOnSecondaryContainer; opacity: 0.55 }
                Rectangle { x: 10; y: 38; width: parent.width * 0.62; height: 6; radius: 3; color: Appearance.colors.colOnSecondaryContainer; opacity: 0.35 }
            }
        }

        // Frame
        Rectangle { visible: pv.frameVisible("top"); color: pv.frameCol; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: pv.frameW }
        Rectangle { visible: pv.frameVisible("bottom"); color: pv.frameCol; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: pv.frameW }
        Rectangle { visible: pv.frameVisible("left"); color: pv.frameCol; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: pv.frameW }
        Rectangle { visible: pv.frameVisible("right"); color: pv.frameCol; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; width: pv.frameW }

        // Rounded screen corners
        Repeater {
            model: [RoundCorner.CornerEnum.TopLeft, RoundCorner.CornerEnum.TopRight, RoundCorner.CornerEnum.BottomLeft, RoundCorner.CornerEnum.BottomRight]
            delegate: RoundCorner {
                id: cornerItem
                required property var modelData
                visible: Config.options.appearance.fakeScreenRounding !== 0
                corner: modelData
                implicitSize: 14
                color: pv.frameOn ? pv.frameCol : "black"
                x: isLeft ? pv.fL : pv.width - width - pv.fR
                y: isTop ? pv.fT : pv.height - height - pv.fB
            }
        }

        // Bar
        Item {
            id: barItem
            x: pv.vertical
                ? (pv.atEnd ? pv.width - pv.fR - pv.barThick - pv.gapAcross : pv.fL + pv.gapAcross)
                : pv.fL + pv.gapAlong
            y: pv.vertical
                ? pv.fT + pv.gapAlong
                : (pv.atEnd ? pv.height - pv.fB - pv.barThick - pv.gapAcross : pv.fT + pv.gapAcross)
            width: pv.vertical ? pv.barThick : pv.width - pv.fL - pv.fR - pv.gapAlong * 2
            height: pv.vertical ? pv.height - pv.fT - pv.fB - pv.gapAlong * 2 : pv.barThick
            readonly property real along: pv.vertical ? height : width

            Rectangle {
                anchors.fill: parent
                visible: pv.barHasBg && !pv.islands && !pv.splitGroups
                radius: pv.attached ? 3 : (pv.barStyle === 3 ? 5 : Math.min(width, height) / 2)
                color: Appearance.colors.colLayer0Base
                opacity: (pv.groupStyle === "pills" || pv.groupStyle === "separated") ? 0.45 : 0.95
            }

            Repeater {
                model: [ { a: 0.02, l: 0.27 }, { a: 0.33, l: 0.34 }, { a: 0.7, l: 0.28 } ]
                delegate: Rectangle {
                    id: groupItem
                    required property var modelData
                    readonly property bool boxed: pv.islands || pv.splitGroups || pv.groupStyle !== "transparent"
                    x: pv.vertical ? 2 : modelData.a * barItem.along
                    y: pv.vertical ? modelData.a * barItem.along : 2
                    width: pv.vertical ? barItem.width - 4 : modelData.l * barItem.along
                    height: pv.vertical ? modelData.l * barItem.along : barItem.height - 4
                    radius: Math.min(width, height) / 2
                    color: boxed ? ((pv.islands || pv.splitGroups) ? Appearance.colors.colLayer0Base : Appearance.colors.colLayer1Base) : "transparent"

                    Grid {
                        anchors.centerIn: parent
                        flow: pv.vertical ? Grid.TopToBottom : Grid.LeftToRight
                        spacing: 4
                        Repeater {
                            model: 3
                            Rectangle {
                                width: 4; height: 4; radius: 2
                                color: Appearance.colors.colOnLayer1
                                opacity: 0.85
                            }
                        }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 6

        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Wallpaper & Colors")
            shape: MaterialShape.Shape.Puffy
            Layout.fillWidth: true
            collapsible: false

            // Live preview + the colors it is painted with
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                ScreenPreview {
                    id: preview
                    Layout.preferredWidth: Math.min(460, Math.round(parent.width * 0.7))
                    Layout.preferredHeight: Math.round(Layout.preferredWidth * 9 / 16)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 8

                    StyledText {
                        text: Translation.tr("Palette")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    GridLayout {
                        columns: 3
                        columnSpacing: 6
                        rowSpacing: 6
                        Repeater {
                            model: [
                                Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary,
                                Appearance.colors.colPrimaryContainer, Appearance.colors.colSecondaryContainer, Appearance.colors.colTertiaryContainer,
                                Appearance.colors.colLayer0Base, Appearance.colors.colLayer1Base, Appearance.colors.colLayer2Base
                            ]
                            delegate: Rectangle {
                                required property color modelData
                                implicitWidth: 30
                                implicitHeight: 30
                                radius: 9
                                color: modelData
                                border.width: 1
                                border.color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("The preview is an approximation of your screen.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            // Controls, each with a name and its current value
            GridLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                columns: 2
                columnSpacing: 24
                rowSpacing: 14

                OptionRow {
                    Layout.alignment: Qt.AlignTop
                    label: Translation.tr("Mode")
                    currentValue: Appearance.m3colors.darkmode
                    options: [
                        { displayName: Translation.tr("Light"), icon: "light_mode", value: false },
                        { displayName: Translation.tr("Dark"), icon: "dark_mode", value: true }
                    ]
                    onSelected: newValue => {
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --mode ${newValue ? "dark" : "light"} --noswitch`]);
                    }
                }

                OptionRow {
                    Layout.alignment: Qt.AlignTop
                    label: Translation.tr("Screen round corner")
                    currentValue: Config.options.appearance.fakeScreenRounding
                    options: [
                        { displayName: Translation.tr("No"), icon: "close", value: 0 },
                        { displayName: Translation.tr("Yes"), icon: "check", value: 1 },
                        { displayName: Translation.tr("When not fullscreen"), icon: "fullscreen_exit", value: 2 }
                    ]
                    onSelected: newValue => { Config.options.appearance.fakeScreenRounding = newValue; }
                }

                OptionRow {
                    id: schemeRow
                    Layout.columnSpan: 2
                    Layout.alignment: Qt.AlignTop
                    readonly property bool namedMode: ColorSchemes.current !== ""
                    label: Translation.tr("Color scheme")
                    currentValue: namedMode ? ColorSchemes.current : Config.options.appearance.palette.type
                    options: namedMode ? [{ displayName: "Material", icon: "auto_awesome", value: "" }].concat(
                        ColorSchemes.schemeOptions().filter(o => o.value !== "").map(o => ({ displayName: o.displayName, icon: "palette", value: o.value }))
                    ) : [
                        { displayName: Translation.tr("Auto"),        icon: "auto_awesome",  value: "auto" },
                        { displayName: Translation.tr("Content"),     icon: "image",         value: "scheme-content" },
                        { displayName: Translation.tr("Expressive"),  icon: "palette",       value: "scheme-expressive" },
                        { displayName: Translation.tr("Fidelity"),    icon: "equal",         value: "scheme-fidelity" },
                        { displayName: Translation.tr("Fruit Salad"), icon: "nutrition",     value: "scheme-fruit-salad" },
                        { displayName: Translation.tr("Mono"),        icon: "invert_colors", value: "scheme-monochrome" },
                        { displayName: Translation.tr("Neutral"),     icon: "tonality",      value: "scheme-neutral" },
                        { displayName: Translation.tr("Rainbow"),     icon: "gradient",      value: "scheme-rainbow" },
                        { displayName: Translation.tr("Tonal Spot"),  icon: "lens",          value: "scheme-tonal-spot" }
                    ]
                    onSelected: newValue => {
                        if (namedMode) {
                            ColorSchemes.setScheme(newValue);
                            return;
                        }
                        Config.options.appearance.palette.type = newValue;
                        Quickshell.execDetached(["bash", "-c", `${Directories.wallpaperSwitchScriptPath} --noswitch`]);
                    }
                }

                RippleButtonWithIcon {
                    Layout.columnSpan: 2
                    visible: ColorSchemes.current === ""
                    materialIcon: "colorize"
                    mainText: Translation.tr("Change accent color")
                    onClicked: Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color"])
                }

                OptionRow {
                    Layout.alignment: Qt.AlignTop
                    label: Translation.tr("Bar position")
                    currentValue: (Config.options.bar.bottom ? 1 : 0) | (Config.options.bar.vertical ? 2 : 0)
                    options: [
                        { displayName: Translation.tr("Top"), icon: "arrow_upward", value: 0 },
                        { displayName: Translation.tr("Left"), icon: "arrow_back", value: 2 },
                        { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: 1 },
                        { displayName: Translation.tr("Right"), icon: "arrow_forward", value: 3 }
                    ]
                    onSelected: newValue => {
                        Config.options.bar.bottom = (newValue & 1) !== 0;
                        Config.options.bar.vertical = (newValue & 2) !== 0;
                    }
                }

                OptionRow {
                    Layout.alignment: Qt.AlignTop
                    label: Translation.tr("Group style")
                    currentValue: Config.options.bar.borderless
                    options: [
                        { displayName: Translation.tr("None"), icon: "block", value: "transparent" },
                        { displayName: Translation.tr("Pills"), icon: "pill", value: "pills" },
                        { displayName: Translation.tr("Separated"), icon: "view_column_2", value: "separated" },
                        { displayName: Translation.tr("Segmented"), icon: "tablet", value: "segmented" }
                    ]
                    onSelected: newValue => { Config.options.bar.borderless = newValue; }
                }

                OptionRow {
                    Layout.columnSpan: 2
                    Layout.alignment: Qt.AlignTop
                    label: Translation.tr("Bar style")
                    currentValue: Config.options.bar.cornerStyle
                    options: [
                        { displayName: Translation.tr("Hug"), icon: "line_curve", value: 0 },
                        { displayName: Translation.tr("Split Hug"), icon: "splitscreen", value: 6 },
                        { displayName: Translation.tr("Float"), icon: "view_day", value: 1 },
                        { displayName: Translation.tr("Islands"), icon: "crop_3_2", value: 2 },
                        { displayName: Translation.tr("M3"), icon: "interests", value: 3 },
                        { displayName: Translation.tr("M3 Hug"), icon: "category", value: 4 },
                        { displayName: Translation.tr("Panel"), icon: "toolbar", value: 5 }
                    ]
                    onSelected: newValue => { Config.options.bar.cornerStyle = newValue; }
                }
            }

            // Screen frame (same options as Settings > Bar)
            ConfigRow {
                Layout.topMargin: 6
                ConfigSwitch {
                    buttonIcon: "panorama_wide_angle"
                    text: Translation.tr("Show Frame")
                    checked: Config.options.bar.showFrame

                    property bool switchReady: false
                    Component.onCompleted: Qt.callLater(() => switchReady = true)

                    onCheckedChanged: {
                        if (switchReady && checked) {
                            GlobalStates.refreshBar();
                        }
                        Config.options.bar.showFrame = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "colors"
                    enabled: Config.options.bar.showFrame
                    text: Translation.tr("Follow Frame Color")
                    checked: Config.options.bar.followFrameColor
                    onCheckedChanged: { Config.options.bar.followFrameColor = checked; }
                }
            }
            ConfigSpinBox {
                id: frameThicknessSpin
                enabled: Config.options.bar.showFrame
                icon: "eraser_size_1"
                text: Translation.tr("Frame thickness")
                from: 2
                to: 10
                stepSize: 1
                // Only write on user edits: a write-back on value changes would also fire while
                // the page loads and could overwrite the saved thickness.
                onValueModified: Config.options.bar.frameThickness = value
                Binding {
                    target: frameThicknessSpin
                    property: "value"
                    value: Config.options.bar.frameThickness
                }
            }
            ColorSelectionArray {
                enabled: Config.options.bar.showFrame
                icon: "imagesearch_roller"
                text: Translation.tr("Frame Color")
                options: ["primaryContainer", "secondaryContainer", "tertiaryContainer", "layer0", "black"]
                currentValue: Config.options.bar.frameColor
                onSelected: newValue => {
                    Config.options.bar.frameColor = newValue
                }
            }
        }
    }
}
