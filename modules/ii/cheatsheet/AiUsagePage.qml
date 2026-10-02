pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * "AI usage" tab of the cheat sheet: plan limits for Claude and ChatGPT side by side.
 * Each provider has a script in scripts/ai/ that reads the local login of its app
 * (Claude Code / Codex) and prints the same JSON shape:
 *   { ok, provider, plan, limitReached, limits: [{key, title, subtitle, percent, resetsAt}],
 *     extra: {kind, enabled, unlimited, balance, spent, limit, currency}, breakdown: [{name, percent}] }
 * Each provider is opt-in (Config.options.cheatsheet.aiUsage.<id>): a disabled provider
 * never runs its script, so nothing is read or sent until the user turns it on.
 * Refreshes every `interval` ms while the tab is visible.
 */
Item {
    id: root

    property bool active: true
    property int interval: 60000
    property real now: Date.now()

    implicitHeight: pageColumn.implicitHeight

    readonly property var providers: [
        {
            "id": "claude",
            "name": "Claude",
            "icon": "claude-symbolic",
            "app": "Claude Code",
            "loginHint": Translation.tr("Install Claude Code and run `claude` once to sign in with your Claude account."),
            "renewHint": Translation.tr("Open Claude Code once (run `claude`) to renew the login, then refresh."),
            "relogHint": Translation.tr("Sign in again in Claude Code (`/login`), then refresh."),
        },
        {
            "id": "chatgpt",
            "name": "ChatGPT",
            "icon": "openai-symbolic",
            "app": "Codex",
            "loginHint": Translation.tr("Install Codex or the ChatGPT desktop app and sign in with your ChatGPT account."),
            "renewHint": Translation.tr("Open Codex / ChatGPT once to renew the login, then refresh."),
            "relogHint": Translation.tr("Sign in again in Codex (`codex login`), then refresh."),
        },
    ]

    function isEnabled(id) {
        return Config.options.cheatsheet.aiUsage[id] === true;
    }
    function setEnabled(id, value) {
        Config.options.cheatsheet.aiUsage[id] = value;
    }
    readonly property var enabledProviders: providers.filter(p => isEnabled(p.id))
    readonly property var disabledProviders: providers.filter(p => !isEnabled(p.id))

    function refresh() {
        for (let i = 0; i < providerRepeater.count; i++) providerRepeater.itemAt(i)?.refresh();
    }

    // ---- shared formatting helpers
    function timeLeft(iso) {
        if (!iso) return "--";
        let s = Math.max(0, Math.round((new Date(iso).getTime() - root.now) / 1000));
        const days = Math.floor(s / 86400); s %= 86400;
        const h = Math.floor(s / 3600); s %= 3600;
        const m = Math.floor(s / 60);
        if (days > 0) return `${days}d ${h}h`;
        if (h > 0) return `${h}h ${m}m`;
        return `${m}m`;
    }
    function resetClock(iso) {
        if (!iso) return "";
        const d = new Date(iso);
        const sameDay = d.toDateString() === new Date(root.now).toDateString();
        const sameYearWeek = Math.abs(d.getTime() - root.now) < 6 * 86400000;
        const fmt = sameDay ? Config.options.time.format
            : sameYearWeek ? `ddd ${Config.options.time.format}`
            : `${Config.options.time.shortDateFormat} ${Config.options.time.format}`;
        return Qt.formatDateTime(d, fmt);
    }
    function severityColor(percent) {
        if (percent == null) return Appearance.colors.colPrimary;
        if (percent >= 90) return Appearance.colors.colError;
        if (percent >= 75) return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.5);
        return Appearance.colors.colPrimary;
    }
    function money(value, currency) {
        if (value == null) return "--";
        const symbol = !currency || currency === "USD" ? "$" : `${currency} `;
        return `${symbol}${Number(value).toFixed(2)}`;
    }
    function planName(plan) {
        if (!plan) return "";
        return plan.charAt(0).toUpperCase() + plan.slice(1);
    }

    // Keeps countdowns and "updated x ago" ticking
    Timer {
        running: root.active
        repeat: true
        interval: 1000
        onTriggered: root.now = Date.now()
    }

    // ---- layout
    ColumnLayout {
        id: pageColumn
        width: parent.width
        spacing: 10

        // Explanation shown while at least one provider is off
        Rectangle {
            Layout.fillWidth: true
            visible: root.disabledProviders.length > 0
            implicitHeight: optInColumn.implicitHeight + 28
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: optInColumn
                anchors {
                    fill: parent
                    margins: 14
                }
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: "privacy_tip"
                        iconSize: 22
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: root.enabledProviders.length === 0
                            ? Translation.tr("Shows how much of your Claude and ChatGPT plan limits you've used. Each one is off until you turn it on: it reads the login of the app already on this PC (Claude Code / Codex) and asks only that provider's servers for your usage. The login is never shown, sent elsewhere or renewed.")
                            : Translation.tr("Also available. Turning it on reads that app's login on this PC and asks only its provider for your usage.")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: root.disabledProviders
                        delegate: RippleButton {
                            id: enableButton
                            required property var modelData
                            implicitHeight: 40
                            implicitWidth: enableRow.implicitWidth + 28
                            buttonRadius: Appearance.rounding.full
                            colBackground: Appearance.colors.colSecondaryContainer
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: root.setEnabled(enableButton.modelData.id, true)
                            contentItem: Item {
                                Row {
                                    id: enableRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    CustomIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 18
                                        height: 18
                                        source: enableButton.modelData.icon
                                        colorize: true
                                        color: Appearance.colors.colOnSecondaryContainer
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Show %1 usage").arg(enableButton.modelData.name)
                                        color: Appearance.colors.colOnSecondaryContainer
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                            }
                            StyledToolTip {
                                text: Translation.tr("Reads the %1 login on this PC. You can turn it off in Settings › Interface › Cheat sheet").arg(enableButton.modelData.app)
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.enabledProviders.length > 0
            Repeater {
                id: providerRepeater
                model: root.enabledProviders
                delegate: ProviderColumn {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    provider: modelData
                }
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            visible: root.enabledProviders.length > 0
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Data from the local %1 login · refreshes every minute · turn off in Settings › Interface › Cheat sheet").arg(root.enabledProviders.map(p => p.app).join(" / "))
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                onClicked: root.refresh()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: Translation.tr("Refresh now")
                }
            }
        }
    }

    // ---------------------------------------------------------------- components

    // One provider: header with logo, limit cards, extra usage, breakdown
    component ProviderColumn: ColumnLayout {
        id: col
        property var provider
        property var usage: null
        property string error: ""
        property bool loading: false
        spacing: 10

        function refresh() {
            if (!proc.running) {
                col.loading = true;
                proc.running = true;
            }
        }

        readonly property string errorText: {
            switch (col.error) {
                case "": return "";
                case "no_credentials": return Translation.tr("%1 login not found. %2").arg(col.provider.app).arg(col.provider.loginHint);
                case "api_key_login": return Translation.tr("%1 is signed in with an API key, which has no plan limits. Sign in with your ChatGPT account to see them.").arg(col.provider.app);
                case "expired": return Translation.tr("Your %1 login expired. %2").arg(col.provider.app).arg(col.provider.renewHint);
                case "unauthorized": return Translation.tr("%1 rejected the login. %2").arg(col.provider.name).arg(col.provider.relogHint);
                case "network": return Translation.tr("Couldn't reach %1. Check your connection.").arg(col.provider.name);
                default: return Translation.tr("Unexpected response from %1.").arg(col.provider.name);
            }
        }
        readonly property string updatedText: {
            if (col.loading && !col.usage) return Translation.tr("Loading…");
            if (!col.usage?.fetchedAt) return "";
            const s = Math.max(0, Math.round(root.now / 1000 - col.usage.fetchedAt));
            if (s < 10) return Translation.tr("Updated just now");
            if (s < 60) return Translation.tr("Updated %1 s ago").arg(s);
            return Translation.tr("Updated %1 min ago").arg(Math.floor(s / 60));
        }

        Process {
            id: proc
            command: ["python3", FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/${col.provider.id}_usage.py`)]
            stdout: StdioCollector {
                onStreamFinished: {
                    col.loading = false;
                    try {
                        const data = JSON.parse(text);
                        if (data.ok) {
                            col.usage = data;
                            col.error = "";
                        } else {
                            col.error = data.error ?? "bad_response";
                        }
                    } catch (e) {
                        col.error = "bad_response";
                    }
                }
            }
            onExited: (code, status) => { if (code !== 0) col.loading = false; }
        }
        Timer {
            running: root.active
            repeat: true
            triggeredOnStart: true
            interval: root.interval
            onTriggered: col.refresh()
        }

        // Header: logo + name + plan + overall status (anchored, so the name sits right next to the logo)
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 72
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            Rectangle {
                id: logoCircle
                anchors {
                    left: parent.left
                    leftMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                width: 48
                height: 48
                radius: width / 2
                color: Appearance.colors.colSecondaryContainer
                CustomIcon {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    source: col.provider.icon
                    colorize: true
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            Column {
                anchors {
                    left: logoCircle.right
                    leftMargin: 12
                    right: statusPill.visible ? statusPill.left : parent.right
                    rightMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                spacing: 0
                Row {
                    spacing: 8
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: col.provider.name
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.huge
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: (col.usage?.plan ?? "").length > 0
                        height: planText.implicitHeight + 6
                        width: planText.implicitWidth + 16
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        StyledText {
                            id: planText
                            anchors.centerIn: parent
                            text: root.planName(col.usage?.plan)
                            color: Appearance.colors.colOnPrimaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
                StyledText {
                    width: parent.width
                    elide: Text.ElideRight
                    text: col.updatedText
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            Rectangle {
                id: statusPill
                anchors {
                    right: parent.right
                    rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                visible: col.usage !== null && col.error === ""
                width: statusRow.implicitWidth + 22
                height: 28
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer2
                Row {
                    id: statusRow
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: col.usage?.limitReached ? Appearance.colors.colError : "#4caf50"
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: col.usage?.limitReached ? Translation.tr("Limit reached") : Translation.tr("Available")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
        }

        // Error banner (last good data stays visible below)
        Rectangle {
            Layout.fillWidth: true
            visible: col.errorText.length > 0
            implicitHeight: errorRow.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colErrorContainer
            RowLayout {
                id: errorRow
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 10
                MaterialSymbol {
                    text: col.error === "network" ? "cloud_off" : "key_off"
                    iconSize: 22
                    color: Appearance.colors.colOnErrorContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.MarkdownText
                    text: col.errorText
                    color: Appearance.colors.colOnErrorContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        // Limits
        Repeater {
            model: col.usage?.limits ?? []
            delegate: LimitCard {
                required property var modelData
                Layout.fillWidth: true
                limit: modelData
            }
        }

        // Extra usage / credits
        Rectangle {
            id: extraCard
            Layout.fillWidth: true
            visible: col.usage !== null
            implicitHeight: extraRow.implicitHeight + 24
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            readonly property var extra: col.usage?.extra ?? null

            RowLayout {
                id: extraRow
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 10
                MaterialSymbol {
                    text: extraCard.extra?.kind === "credits" ? "toll" : "payments"
                    iconSize: 22
                    color: Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: extraCard.extra?.kind === "credits" ? Translation.tr("Credits") : Translation.tr("Extra usage")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: {
                            const e = extraCard.extra;
                            if (!e) return "";
                            if (e.unlimited) return Translation.tr("Unlimited");
                            if (!e.enabled) return e.kind === "credits" ? Translation.tr("No credits · usage stops at the plan limits") : Translation.tr("Off · usage stops at the plan limits");
                            if (e.limit) return Translation.tr("of %1 monthly limit").arg(root.money(e.limit, e.currency));
                            return Translation.tr("Used after hitting plan limits");
                        }
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                StyledText {
                    text: {
                        const e = extraCard.extra;
                        if (!e) return "";
                        if (!e.enabled && !e.unlimited) return "";
                        if (e.kind === "credits") return e.balance != null ? `${Math.round(e.balance)}` : "";
                        return root.money(e.spent ?? 0, e.currency);
                    }
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.family: Appearance.font.family.numbers
                }
            }
        }

        // Weekly breakdown per product (Claude only)
        Rectangle {
            Layout.fillWidth: true
            visible: (col.usage?.breakdown?.length ?? 0) > 0
            implicitHeight: breakdownColumn.implicitHeight + 24
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1
            ColumnLayout {
                id: breakdownColumn
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 8
                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: "donut_small"
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: Translation.tr("This week by product")
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                }
                Repeater {
                    model: col.usage?.breakdown ?? []
                    delegate: UsageBar {
                        required property var modelData
                        label: modelData.name
                        percent: modelData.percent
                        colorBySeverity: false
                    }
                }
            }
        }
    }

    component LimitCard: Rectangle {
        id: limitCard
        property var limit
        implicitHeight: limitRow.implicitHeight + 28
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        RowLayout {
            id: limitRow
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 16

            Item {
                implicitWidth: 96
                implicitHeight: 96
                CircularProgress {
                    anchors.centerIn: parent
                    implicitSize: 96
                    lineWidth: 7
                    value: Math.max(0, Math.min(1, (limitCard.limit?.percent ?? 0) / 100))
                    colPrimary: root.severityColor(limitCard.limit?.percent)
                    colSecondary: Appearance.colors.colLayer2
                    enableAnimation: true
                    animationDuration: 600
                }
                Column {
                    anchors.centerIn: parent
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: limitCard.limit?.percent != null ? `${Math.round(limitCard.limit.percent)}%` : "--"
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.family: Appearance.font.family.numbers
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Translation.tr("used")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr(limitCard.limit?.title ?? "")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.large
                }
                StyledText {
                    visible: text.length > 0
                    text: Translation.tr(limitCard.limit?.subtitle ?? "")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                Item { implicitHeight: 4 }
                StyledText {
                    text: Translation.tr("Resets in %1").arg(root.timeLeft(limitCard.limit?.resetsAt))
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: {
                        const clock = root.resetClock(limitCard.limit?.resetsAt);
                        const left = Translation.tr("%1% left").arg(Math.max(0, 100 - Math.round(limitCard.limit?.percent ?? 0)));
                        return clock.length > 0 ? `${clock} · ${left}` : left;
                    }
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    component UsageBar: ColumnLayout {
        id: bar
        property string label
        property real percent: 0
        property bool colorBySeverity: true
        readonly property real fraction: Math.max(0, Math.min(1, percent / 100))
        Layout.fillWidth: true
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                text: bar.label
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                text: `${Math.round(bar.percent)}%`
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 7
            radius: height / 2
            color: Appearance.colors.colSecondaryContainer
            Rectangle {
                visible: bar.fraction > 0
                height: parent.height
                width: Math.max(height, parent.width * bar.fraction)
                radius: height / 2
                color: bar.colorBySeverity ? root.severityColor(bar.percent) : Appearance.colors.colPrimary
                Behavior on width {
                    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
