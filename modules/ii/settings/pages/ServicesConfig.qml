import qs
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true
    bottomContentPadding: 15
    
    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "neurology"
            shape: MaterialShape.Shape.Ghostish
            title: Translation.tr("AI")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("System prompt")
                text: Config.options.ai.systemPrompt
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Qt.callLater(() => {
                        Config.options.ai.systemPrompt = text;
                    });
                }
            }
        }

        ContentSection {
            icon: "cell_tower"
            shape: MaterialShape.Shape.PixelCircle
            title: Translation.tr("Networking")

            MaterialTextArea {
                Layout.fillWidth: true
                placeholderText: Translation.tr("User agent (for services that require it)")
                text: Config.options.networking.userAgent
                wrapMode: TextEdit.Wrap
                onTextChanged: {
                    Config.options.networking.userAgent = text;
                }
            }
        }

        ContentSection {
            icon: "music_cast"
            shape: MaterialShape.Shape.Oval
            title: Translation.tr("Music Recognition")

            GroupedList {
                ConfigSpinBox {
                    icon: "timer_off"
                    text: Translation.tr("Total duration timeout (s)")
                    value: Config.options.musicRecognition.timeout
                    from: 10
                    to: 100
                    stepSize: 2
                    onValueChanged: {
                        Config.options.musicRecognition.timeout = value;
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (s)")
                    value: Config.options.musicRecognition.interval
                    from: 2
                    to: 10
                    stepSize: 1
                    onValueChanged: {
                        Config.options.musicRecognition.interval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "file_open"
            shape: MaterialShape.Shape.Slanted
            title: Translation.tr("Save paths")

            GroupedList {
                ConfigTextArea {
                    id: videoRecordPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "video_file"
                    text: Translation.tr("Video Recording Path")
                    value: Config.options.screenRecord.savePath
                    onValueChanged: {
                        videoRecordPathDebounceTimer.restart();
                    }

                    Timer {
                        id: videoRecordPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenRecord.savePath = videoRecordPathField.value;
                        }
                    }
                }

                ConfigTextArea {
                    id: screenshotPathField
                    Layout.fillWidth: true
                    fieldWidth: 250
                    buttonIcon: "screenshot_monitor"
                    text: Translation.tr("Screenshot Path (leave empty to just copy)")
                    value: Config.options.screenSnip.savePath
                    onValueChanged: {
                        screenshotPathDebounceTimer.restart();
                    }

                    Timer {
                        id: screenshotPathDebounceTimer
                        interval: 600
                        repeat: false
                        onTriggered: {
                            Config.options.screenSnip.savePath = screenshotPathField.value;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "search"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Search")

            GroupedList {
                ConfigSwitch {
                    text: Translation.tr("Use Levenshtein distance-based algorithm instead of fuzzy")
                    checked: Config.options.search.sloppy
                    onCheckedChanged: {
                        Config.options.search.sloppy = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "preview"
                    text: Translation.tr("Show clipboard preview popups")
                    checked: Config.options.search.clipboardPreviewPopup
                    onCheckedChanged: {
                        Config.options.search.clipboardPreviewPopup = checked;
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Prefixes")

                GroupedList {
                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "bolt"
                            fieldWidth: 100
                            text: Translation.tr("Action")
                            value: Config.options.search.prefix.action
                            onValueChanged: {
                                Config.options.search.prefix.action = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "content_paste"
                            fieldWidth: 100
                            text: Translation.tr("Clipboard")
                            value: Config.options.search.prefix.clipboard
                            onValueChanged: {
                                Config.options.search.prefix.clipboard = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "mood"
                            fieldWidth: 100
                            text: Translation.tr("Emojis")
                            value: Config.options.search.prefix.emojis
                            onValueChanged: {
                                Config.options.search.prefix.emojis = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "emoji_symbols"
                            fieldWidth: 100
                            text: Translation.tr("Icons")
                            value: Config.options.search.prefix.symbols
                            onValueChanged: {
                                Config.options.search.prefix.symbols = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "terminal"
                            fieldWidth: 100
                            text: Translation.tr("Shell command")
                            value: Config.options.search.prefix.shellCommand
                            onValueChanged: {
                                Config.options.search.prefix.shellCommand = value;
                            }
                        }
                        ConfigTextArea {
                            Layout.fillWidth: true
                            fieldWidth: 100
                            buttonIcon: "travel_explore"
                            text: Translation.tr("Web search")
                            value: Config.options.search.prefix.webSearch
                            onValueChanged: {
                                Config.options.search.prefix.webSearch = value;
                            }
                        }
                    }

                    ConfigRow {
                        uniform: true
                        ConfigTextArea {
                            Layout.fillWidth: true
                            buttonIcon: "apps"
                            fieldWidth: 100
                            text: Translation.tr("Apps")
                            value: Config.options.search.prefix.app
                            onValueChanged: {
                                Config.options.search.prefix.app = value;
                            }
                        }
                    }
                }
            }
            ContentSubsection {
                title: Translation.tr("Web search")

                GroupedList {
                    ConfigTextArea {
                        id: baseUrlField
                        Layout.fillWidth: true
                        fieldWidth: 320
                        buttonIcon: "travel_explore"
                        text: Translation.tr("Base URL")
                        value: Config.options.search.engineBaseUrl
                        onValueChanged: {
                            baseUrlDebounceTimer.restart();
                        }

                        Timer {
                            id: baseUrlDebounceTimer
                            interval: 600
                            repeat: false
                            onTriggered: {
                                Config.options.search.engineBaseUrl = baseUrlField.value;
                            }
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "deployed_code_update"
            title: Translation.tr("System updates (Arch only)")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "update"
                    text: Translation.tr("Enable update checks")
                    checked: Config.options.updates.enableCheck
                    onCheckedChanged: {
                        Config.options.updates.enableCheck = checked;
                    }
                }

                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Check interval (mins)")
                    value: Config.options.updates.checkInterval
                    from: 60
                    to: 1440
                    stepSize: 60
                    onValueChanged: {
                        Config.options.updates.checkInterval = value;
                    }
                }
            }
        }

        ContentSection {
            icon: "sports_esports"
            shape: MaterialShape.Shape.Cookie6Sided
            title: Translation.tr("Gamepad")

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "sports_esports"
                    text: Translation.tr("Open a panel with a controller button")
                    checked: Config.options.gamepad.enable
                    onCheckedChanged: { Config.options.gamepad.enable = checked }
                    StyledToolTip {
                        text: Translation.tr("Watches connected game controllers (USB or Bluetooth).\nGames still receive every button as usual.")
                    }
                }
                ConfigComboBox {
                    Layout.fillWidth: true
                    enabled: Config.options.gamepad.enable
                    buttonIcon: "open_in_new"
                    text: Translation.tr("Action")
                    textRole: "displayName"
                    model: GlobalStates.hotCornerOptions.filter(o => o.value !== "none")
                    currentValue: Config.options.gamepad.action
                    onSelected: newValue => { Config.options.gamepad.action = newValue }
                }
            }

            ContentSubsection {
                title: Translation.tr("Button")
                tooltip: Translation.tr("Click \"Pick\" and press the button you want on the controller")
                enabled: Config.options.gamepad.enable

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    MaterialSymbol {
                        text: "gamepad"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Gamepad.learning ? Translation.tr("Press a button on the controller…")
                            : Gamepad.buttonLabel(Config.options.gamepad.button)
                        color: Gamepad.learning ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    }
                    RippleButtonWithIcon {
                        materialIcon: Gamepad.learning ? "close" : "ads_click"
                        mainText: Gamepad.learning ? Translation.tr("Cancel") : Translation.tr("Pick")
                        enabled: Gamepad.learning || Gamepad.devices.length > 0
                        onClicked: Gamepad.learning ? Gamepad.cancelLearning() : Gamepad.startLearning()
                    }
                    RippleButtonWithIcon {
                        visible: Config.options.gamepad.button !== "BTN_MODE" && !Gamepad.learning
                        materialIcon: "restart_alt"
                        mainText: Translation.tr("Default")
                        onClicked: Config.options.gamepad.button = "BTN_MODE"
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Status")
                visible: Config.options.gamepad.enable
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: Gamepad.error !== "" ? "error" : Gamepad.devices.length > 0 ? "check_circle" : "videogame_asset_off"
                        iconSize: 22
                        color: Gamepad.error !== "" ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colOnLayer1
                        text: {
                            switch (Gamepad.error) {
                            case "no_evdev": return Translation.tr("The python-evdev package is missing. Install it (Arch: sudo pacman -S python-evdev) and toggle this off and on.");
                            case "no_permission": return Translation.tr("No permission to read controllers. Add your user to the \"input\" group (sudo usermod -aG input $USER) and log in again.");
                            case "crashed": return Translation.tr("The controller listener stopped unexpectedly; retrying…");
                            }
                            if (Gamepad.devices.length === 0) return Translation.tr("No controller connected. Plug one in or pair it; it's detected automatically.");
                            let s = Translation.tr("Connected: %1").arg(Gamepad.devices.join(", "));
                            if (Gamepad.lastPressed) s += "\n" + Translation.tr("Last press: %1").arg(Gamepad.lastPressed);
                            return s;
                        }
                    }
                }
            }
        }

        ContentSection {
            icon: "weather_mix"
            shape: MaterialShape.Shape.Pill
            title: Translation.tr("Weather")
            GroupedList {
                ConfigSwitch {
                    buttonIcon: "assistant_navigation"
                    text: Translation.tr("Enable GPS based location")
                    checked: Config.options.bar.weather.enableGPS
                    onCheckedChanged: {
                        Config.options.bar.weather.enableGPS = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "thermometer"
                    text: Translation.tr("Fahrenheit unit")
                    checked: Config.options.bar.weather.useUSCS
                    onCheckedChanged: {
                        Config.options.bar.weather.useUSCS = checked;
                    }
                }
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Polling interval (m)")
                    value: Config.options.bar.weather.fetchInterval
                    from: 5
                    to: 50
                    stepSize: 5
                    onValueChanged: {
                        Config.options.bar.weather.fetchInterval = value;
                    }
                }
                ConfigTextArea {
                    id: cityField
                    Layout.fillWidth: true
                    buttonIcon: "location_city"
                    text: Translation.tr("City name")
                    value: Config.options.bar.weather.city
                    onValueChanged: cityDebounceTimer.restart()

                    Timer {
                        id: cityDebounceTimer
                        interval: 1000
                        running: false
                        onTriggered: Config.options.bar.weather.city = cityField.value
                    }
                }
            }
        }
        WorldMap {
            Layout.fillWidth: true
            Layout.preferredHeight: 300
        }
    }
}
