import qs
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/sddm/sddm_apply.py`)
    readonly property string installPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/sddm/install.sh`)
    readonly property string imagePath: Config.options.sddm.useShellWallpaper
        ? Config.options.background.wallpaperPath
        : Config.options.sddm.customImage
    readonly property bool imageOk: /\.(png|jpe?g|webp)$/i.test(imagePath)
    readonly property var colorRows: [
        { key: "DateColor", label: Translation.tr("Date"), icon: "calendar_today" },
        { key: "TimeColor", label: Translation.tr("Clock"), icon: "schedule" },
        { key: "InputColor", label: Translation.tr("Text box background"), icon: "input" },
        { key: "InputTextColor", label: Translation.tr("Text box text"), icon: "text_fields" },
        { key: "InputBorderColor", label: Translation.tr("Text box border"), icon: "border_style" },
        { key: "LoginButtonColor", label: Translation.tr("Login button"), icon: "login" },
        { key: "LoginButtonTextColor", label: Translation.tr("Login button text"), icon: "match_case" },
        { key: "SessionButtonColor", label: Translation.tr("Session button"), icon: "desktop_windows" },
        { key: "SessionIconColor", label: Translation.tr("Session button icon"), icon: "desktop_windows" },
        { key: "PowerButtonColor", label: Translation.tr("Power button"), icon: "power_settings_new" },
        { key: "PowerIconColor", label: Translation.tr("Power button icon"), icon: "power_settings_new" },
        { key: "PopupColor", label: Translation.tr("Menus (popups)"), icon: "menu" },
        { key: "PopupActiveColor", label: Translation.tr("Menu selected item"), icon: "check_box" },
        { key: "PopupActiveTextColor", label: Translation.tr("Menu selected text"), icon: "format_color_text" },
        { key: "UserColor", label: Translation.tr("User name text"), icon: "person" },
        { key: "UserBorderColor", label: Translation.tr("User photo border"), icon: "account_circle" }
    ]
    property string status: ""
    property bool statusError: false
    property bool needsInstall: false

    function apply() {
        const opts = Config.options.sddm;
        const args = ["python3", page.scriptPath, "--image", page.imagePath, "--radius", String(opts.radius), "--login-text", opts.loginText];
        if (!opts.autoColors) args.push("--no-colors");
        args.push("--font-family", opts.fontFamily, "--date-size", String(opts.dateSize), "--time-size", String(opts.timeSize));
        for (const row of page.colorRows) {
            const v = opts["c" + row.key];
            if (/^#[0-9a-fA-F]{6}$/.test(v)) args.push("--set", row.key + "=" + v);
        }
        if (opts.userPicture) args.push("--user-picture");
        if (opts.showPassword) args.push("--show-password");
        if (opts.clock24h) args.push("--clock24");
        page.status = Translation.tr("Applying...");
        page.statusError = false;
        applyProc.command = args;
        applyProc.running = true;
    }

    Process {
        id: applyProc
        stdout: StdioCollector { id: outCollector }
        stderr: StdioCollector { id: errCollector }
        onExited: (code) => {
            const err = errCollector.text.trim();
            page.needsInstall = code !== 0 && (err.includes("password is required") || err.includes("command not found") || err.includes("No such file"));
            page.statusError = code !== 0;
            page.status = code === 0
                ? Translation.tr("Applied. The new look shows up at the next login screen.")
                : (page.needsInstall ? Translation.tr("The root helper is not installed yet. Run the installer below once.") : err);
        }
    }


    component ColorRow: RowLayout {
        id: cr
        required property var rowData
        readonly property string cfgKey: "c" + rowData.key
        readonly property string current: Config.options.sddm[cfgKey]
        readonly property bool valid: /^#[0-9a-fA-F]{6}$/.test(current)
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        spacing: 10
        OptionalMaterialSymbol { icon: cr.rowData.icon; iconSize: Appearance.font.pixelSize.larger }
        Item {
            Layout.fillWidth: true
            implicitHeight: crLabel.implicitHeight
            StyledText {
                id: crLabel
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                elide: Text.ElideRight
                text: cr.rowData.label
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            radius: Appearance.rounding.full
            color: cr.valid ? cr.current : "transparent"
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            StyledText {
                anchors.centerIn: parent
                visible: !cr.valid
                text: "A"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        ConfigTextArea {
            Layout.fillWidth: false
            Layout.leftMargin: 0
            Layout.rightMargin: 0
            fieldWidth: 110
            placeholderText: Translation.tr("auto")
            value: cr.current
            onValueChanged: Config.options.sddm[cr.cfgKey] = value.trim()
        }
        RippleButton {
            implicitWidth: 32
            implicitHeight: 32
            buttonRadius: Appearance.rounding.full
            enabled: cr.current !== ""
            onClicked: Config.options.sddm[cr.cfgKey] = ""
            contentItem: Item {
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "restart_alt"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 20

        ContentSection {
            icon: "login"
            shape: MaterialShape.Shape.Cookie7Sided
            title: Translation.tr("Login screen (SDDM)")

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Theme: corners. Changes are written only when you press Apply.")
            }

            ContentSubsection {
                title: Translation.tr("Background image")

                ConfigSelectionArray {
                    currentValue: Config.options.sddm.useShellWallpaper ? "shell" : "custom"
                    options: [
                        { "displayName": Translation.tr("Current wallpaper"), "icon": "wallpaper", "value": "shell" },
                        { "displayName": Translation.tr("Pick another image"), "icon": "image", "value": "custom" },
                    ]
                    onSelected: newValue => {
                        Config.options.sddm.useShellWallpaper = newValue === "shell";
                        if (newValue === "custom") {
                            GlobalStates.wallpaperSelectorTarget = "sddmWall";
                            GlobalStates.wallpaperSelectorOpen = true;
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 190
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    clip: true

                    Image {
                        anchors.fill: parent
                        visible: page.imageOk
                        source: page.imageOk ? "file://" + page.imagePath : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 800
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: !page.imageOk
                        width: parent.width - 32
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("The selected wallpaper is not a PNG/JPG/WEBP image (live wallpaper?). Pick another image.")
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Colors")

                ConfigSwitch {
                    buttonIcon: "palette"
                    text: Translation.tr("Generate colors from the wallpaper palette")
                    checked: Config.options.sddm.autoColors
                    onCheckedChanged: Config.options.sddm.autoColors = checked
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: Config.options.sddm.autoColors
                    Repeater {
                        model: [
                            Appearance.colors.colPrimary, Appearance.colors.colOnPrimary,
                            Appearance.colors.colSecondaryContainer, Appearance.colors.colOnSecondaryContainer,
                            Appearance.colors.colLayer2, Appearance.colors.colOnLayer1
                        ]
                        Rectangle {
                            required property color modelData
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: Appearance.rounding.full
                            color: modelData
                            border.width: 1
                            border.color: Appearance.colors.colOutlineVariant
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Features")

                ConfigSwitch {
                    buttonIcon: "account_circle"
                    text: Translation.tr("Show user photo above the login fields")
                    checked: Config.options.sddm.userPicture
                    onCheckedChanged: Config.options.sddm.userPicture = checked
                }
                ConfigSwitch {
                    buttonIcon: "visibility"
                    text: Translation.tr("Show password while typing")
                    checked: Config.options.sddm.showPassword
                    onCheckedChanged: Config.options.sddm.showPassword = checked
                }
                ConfigSwitch {
                    buttonIcon: "schedule"
                    text: Translation.tr("24-hour clock")
                    checked: Config.options.sddm.clock24h
                    onCheckedChanged: Config.options.sddm.clock24h = checked
                }
                ConfigSpinBox {
                    icon: "rounded_corner"
                    text: Translation.tr("Corner radius")
                    value: Config.options.sddm.radius
                    from: 0
                    to: 40
                    stepSize: 2
                    onValueChanged: Config.options.sddm.radius = value
                }
                ConfigTextArea {
                    Layout.fillWidth: true
                    fieldWidth: 200
                    buttonIcon: "login"
                    text: Translation.tr("Login button text")
                    value: Config.options.sddm.loginText
                    onValueChanged: Config.options.sddm.loginText = value
                }
            }

            ContentSubsection {
                title: Translation.tr("Fonts and sizes")

                ConfigComboBox {
                    Layout.fillWidth: true
                    buttonIcon: "text_fields"
                    text: Translation.tr("Font (whole login screen)")
                    fieldWidth: 260
                    fixedWidth: true
                    searchable: true
                    model: {
                        const opts = SystemAppearance.toOptions(SystemAppearance.fonts);
                        const cur = Config.options.sddm.fontFamily;
                        return opts.some(o => o.value === cur) ? opts : [{ displayName: cur, value: cur }].concat(opts);
                    }
                    currentValue: Config.options.sddm.fontFamily
                    onSelected: newValue => Config.options.sddm.fontFamily = newValue
                }
                ConfigSpinBox {
                    icon: "calendar_today"
                    text: Translation.tr("Date size")
                    value: Config.options.sddm.dateSize
                    from: 8
                    to: 120
                    stepSize: 2
                    onValueChanged: Config.options.sddm.dateSize = value
                }
                ConfigSpinBox {
                    icon: "schedule"
                    text: Translation.tr("Clock size")
                    value: Config.options.sddm.timeSize
                    from: 8
                    to: 120
                    stepSize: 2
                    onValueChanged: Config.options.sddm.timeSize = value
                }
            }

            ContentSubsection {
                title: Translation.tr("Custom colors")

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Type a hex color like #ff8800 to override one element. Empty (auto) uses the wallpaper palette, or keeps the current login screen color if the palette is off.")
                }
                Repeater {
                    model: page.colorRows
                    delegate: ColorRow { required property var modelData; rowData: modelData }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                RippleButton {
                    implicitWidth: applyLabel.implicitWidth + 32
                    implicitHeight: 40
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    enabled: page.imageOk && !applyProc.running
                    onClicked: page.apply()
                    contentItem: Item {
                        StyledText {
                            id: applyLabel
                            anchors.centerIn: parent
                            text: Translation.tr("Apply to SDDM")
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    visible: page.status !== ""
                    text: page.status
                    color: page.statusError ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: page.needsInstall
                implicitHeight: setupCol.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: setupCol
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer2
                        text: Translation.tr("One-time setup needed")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("1. Press \"Copy command\" and paste it in a terminal (Ctrl+Shift+V).\n2. The script explains what it does and asks to continue (y/s + Enter).\n3. It asks for YOUR user password (the sudo one). Nothing shows while typing - that's normal. Type it and press Enter.\n4. When it says \"Done\", come back here and press Apply again.")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        font.family: Appearance.font.family.monospace
                        color: Appearance.colors.colOnLayer2
                        text: "bash '" + page.installPath + "'"
                    }
                    RippleButton {
                        implicitWidth: copyLabel.implicitWidth + 32
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        onClicked: Quickshell.clipboardText = "bash '" + page.installPath + "'"
                        contentItem: Item {
                            StyledText {
                                id: copyLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Copy command")
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }
    }
}
