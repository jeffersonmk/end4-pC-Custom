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
 * "Claude" tab of the cheat sheet: Claude plan limits (current 5-hour session,
 * weekly limit, per-model weekly limits, extra-usage spend, weekly breakdown).
 * Data comes from scripts/claude/claude_usage.py, which reads the Claude Code
 * login. Refreshes every `interval` ms while the tab is visible.
 */
Item {
    id: root

    property bool active: true
    property int interval: 60000

    property var usage: null       // last successful response
    property string error: ""      // error code of the last attempt ("" = ok)
    property bool loading: false
    property real now: Date.now()

    implicitHeight: pageColumn.implicitHeight

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/claude/claude_usage.py`)

    function refresh() {
        if (!usageProc.running) {
            root.loading = true;
            usageProc.running = true;
        }
    }

    // ---- formatting helpers
    function resetDate(iso) {
        return iso ? new Date(iso) : null;
    }
    function timeLeft(iso) {
        const d = resetDate(iso);
        if (!d) return "--";
        let s = Math.max(0, Math.round((d.getTime() - root.now) / 1000));
        const days = Math.floor(s / 86400); s %= 86400;
        const h = Math.floor(s / 3600); s %= 3600;
        const m = Math.floor(s / 60);
        if (days > 0) return `${days}d ${h}h`;
        if (h > 0) return `${h}h ${m}m`;
        return `${Math.max(m, 0)}m`;
    }
    function resetClock(iso) {
        const d = resetDate(iso);
        if (!d) return "";
        const sameDay = d.toDateString() === new Date(root.now).toDateString();
        return Qt.formatDateTime(d, sameDay ? Config.options.time.format : `ddd ${Config.options.time.format}`);
    }
    function severityColor(percent) {
        if (percent == null) return Appearance.colors.colPrimary;
        if (percent >= 90) return Appearance.colors.colError;
        if (percent >= 75) return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.5);
        return Appearance.colors.colPrimary;
    }
    function money(value, currency) {
        if (value == null) return "--";
        const symbol = currency === "USD" ? "$" : `${currency} `;
        return `${symbol}${value.toFixed(2)}`;
    }
    function updatedText() {
        if (!root.usage?.fetchedAt) return "";
        const s = Math.max(0, Math.round(root.now / 1000 - root.usage.fetchedAt));
        if (s < 10) return Translation.tr("Updated just now");
        if (s < 60) return Translation.tr("Updated %1 s ago").arg(s);
        return Translation.tr("Updated %1 min ago").arg(Math.floor(s / 60));
    }
    readonly property string errorText: {
        switch (root.error) {
            case "": return "";
            case "no_credentials": return Translation.tr("Claude Code login not found. Install Claude Code and run `claude` once to sign in with your Claude account.");
            case "expired": return Translation.tr("Your Claude Code login expired. Open Claude Code once (run `claude`) to renew it, then refresh.");
            case "unauthorized": return Translation.tr("Claude rejected the login. Sign in again in Claude Code (`/login`), then refresh.");
            case "network": return Translation.tr("Couldn't reach claude.ai. Check your connection.");
            default: return Translation.tr("Unexpected response from claude.ai.");
        }
    }

    // ---- data
    Process {
        id: usageProc
        command: ["python3", root.scriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const data = JSON.parse(text);
                    if (data.ok) {
                        root.usage = data;
                        root.error = "";
                    } else {
                        root.error = data.error ?? "bad_response";
                    }
                } catch (e) {
                    root.error = "bad_response";
                }
            }
        }
        onExited: (code, status) => { if (code !== 0) root.loading = false; }
    }
    Timer {
        running: root.active
        repeat: true
        triggeredOnStart: true
        interval: root.interval
        onTriggered: root.refresh()
    }
    // Keeps the countdowns and "updated x ago" ticking
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

        // Error banner (keeps showing the last good data below it, if any)
        Rectangle {
            Layout.fillWidth: true
            visible: root.errorText.length > 0
            implicitHeight: errorRow.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: Appearance.colors.colErrorContainer ?? Appearance.colors.colLayer1
            RowLayout {
                id: errorRow
                anchors {
                    fill: parent
                    margins: 12
                }
                spacing: 10
                MaterialSymbol {
                    text: root.error === "network" ? "cloud_off" : "key_off"
                    iconSize: 22
                    color: Appearance.colors.colOnErrorContainer ?? Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.MarkdownText
                    text: root.errorText
                    color: Appearance.colors.colOnErrorContainer ?? Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }

        // Session + Weekly
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.usage !== null

            LimitCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                icon: "timer"
                title: Translation.tr("Current session")
                subtitle: Translation.tr("5-hour window")
                percent: root.usage?.session?.percent ?? null
                resetsAt: root.usage?.session?.resetsAt ?? ""
            }
            LimitCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                icon: "date_range"
                title: Translation.tr("Weekly limit")
                subtitle: Translation.tr("All models")
                percent: root.usage?.weekly?.percent ?? null
                resetsAt: root.usage?.weekly?.resetsAt ?? ""
            }
        }

        // Per-model weekly limits (only on plans that have them)
        Repeater {
            model: root.usage?.weeklyModels ?? []
            delegate: Card {
                id: modelCard
                required property var modelData
                Layout.fillWidth: true
                icon: "neurology"
                title: Translation.tr("Weekly · %1").arg(modelCard.modelData.name)
                UsageBar {
                    label: Translation.tr("Resets in %1 (%2)").arg(root.timeLeft(modelCard.modelData.resetsAt)).arg(root.resetClock(modelCard.modelData.resetsAt))
                    percent: modelCard.modelData.percent
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            visible: root.usage !== null

            // Where the weekly usage went
            Card {
                Layout.fillWidth: true
                Layout.preferredWidth: 3
                Layout.fillHeight: true
                icon: "donut_small"
                title: Translation.tr("Weekly usage by product")
                details: Translation.tr("Share of this week's usage")
                Repeater {
                    model: root.usage?.breakdown ?? []
                    delegate: UsageBar {
                        required property var modelData
                        label: modelData.name
                        percent: modelData.percent
                        colorBySeverity: false
                    }
                }
            }

            // Extra usage (pay-as-you-go credits)
            Card {
                Layout.fillWidth: true
                Layout.preferredWidth: 2
                Layout.fillHeight: true
                icon: "payments"
                title: Translation.tr("Extra usage")
                details: root.usage?.extraUsage?.enabled ? Translation.tr("Credits used after hitting plan limits") : Translation.tr("Off · usage stops at the plan limits")
                StyledText {
                    text: root.money(root.usage?.extraUsage?.spent ?? 0, root.usage?.extraUsage?.currency ?? "USD")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.title
                    font.family: Appearance.font.family.numbers
                }
                UsageBar {
                    visible: (root.usage?.extraUsage?.limit ?? 0) > 0
                    label: Translation.tr("of %1 monthly limit").arg(root.money(root.usage?.extraUsage?.limit, root.usage?.extraUsage?.currency ?? "USD"))
                    percent: (root.usage?.extraUsage?.limit ?? 0) > 0 ? 100 * (root.usage?.extraUsage?.spent ?? 0) / root.usage.extraUsage.limit : 0
                }
                Item { Layout.fillHeight: true }
            }
        }

        // Footer
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StyledText {
                Layout.fillWidth: true
                text: root.loading && !root.usage ? Translation.tr("Loading…") : root.updatedText()
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                text: Translation.tr("Data from your Claude Code login")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer1
                enabled: !root.loading
                onClicked: root.refresh()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: "refresh"
                    iconSize: 18
                    color: Appearance.colors.colOnLayer1
                    RotationAnimation on rotation {
                        running: root.loading
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Refresh now")
                }
            }
        }
    }

    // ---------------------------------------------------------------- components
    component Card: Rectangle {
        id: card
        property string icon
        property string title
        property string details: ""
        default property alias content: cardBody.data
        implicitHeight: cardColumn.implicitHeight + 28
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        ColumnLayout {
            id: cardColumn
            anchors {
                fill: parent
                margins: 14
            }
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: width / 2
                    color: Appearance.colors.colSecondaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: card.icon
                        iconSize: 21
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: card.title
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.large
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: card.details
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            ColumnLayout {
                id: cardBody
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
            }
        }
    }

    component LimitCard: Rectangle {
        id: limit
        property string icon
        property string title
        property string subtitle
        property var percent: null
        property string resetsAt: ""
        implicitHeight: limitRow.implicitHeight + 32
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1

        RowLayout {
            id: limitRow
            anchors {
                fill: parent
                margins: 16
            }
            spacing: 18

            Item {
                implicitWidth: 120
                implicitHeight: 120
                CircularProgress {
                    anchors.centerIn: parent
                    implicitSize: 120
                    lineWidth: 8
                    value: Math.max(0, Math.min(1, (limit.percent ?? 0) / 100))
                    colPrimary: root.severityColor(limit.percent)
                    colSecondary: Appearance.colors.colLayer2
                    enableAnimation: true
                    animationDuration: 600
                }
                Column {
                    anchors.centerIn: parent
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: limit.percent != null ? `${Math.round(limit.percent)}%` : "--"
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.title
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
                spacing: 4
                RowLayout {
                    spacing: 8
                    MaterialSymbol {
                        text: limit.icon
                        iconSize: 20
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: limit.title
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.large
                    }
                }
                StyledText {
                    text: limit.subtitle
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                Item { implicitHeight: 6 }
                StyledText {
                    text: Translation.tr("Resets in %1").arg(root.timeLeft(limit.resetsAt))
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
                StyledText {
                    visible: text.length > 0
                    text: root.resetClock(limit.resetsAt)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                StyledText {
                    visible: limit.percent != null
                    text: Translation.tr("%1% left").arg(Math.max(0, 100 - Math.round(limit.percent ?? 0)))
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
        spacing: 5

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
            implicitHeight: 8
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
