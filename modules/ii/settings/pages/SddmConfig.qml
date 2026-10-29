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
    property string status: ""
    property bool statusError: false
    property bool needsInstall: false

    function apply() {
        const opts = Config.options.sddm;
        const args = ["python3", page.scriptPath, "--image", page.imagePath, "--radius", String(opts.radius), "--login-text", opts.loginText];
        if (!opts.autoColors) args.push("--no-colors");
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

            StyledText {
                Layout.fillWidth: true
                visible: page.needsInstall
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Appearance.colors.colSubtext
                text: Translation.tr("One-time setup (asks your password once):") + "\n    bash " + page.installPath
            }
        }
    }
}
