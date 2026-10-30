import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// Hover details of the AI Usage bar widget: every plan limit of each shown provider
StyledPopup {
    id: root
    property var providers: []

    function severityColor(percent) {
        if (percent >= 90) return Appearance.colors.colError;
        if (percent >= 75) return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.5);
        return Appearance.colors.colPrimary;
    }
    function planName(plan) {
        if (!plan) return "";
        return plan.charAt(0).toUpperCase() + plan.slice(1);
    }

    ColumnLayout {
        spacing: 12

        Repeater {
            model: root.providers
            delegate: ColumnLayout {
                id: provider
                required property var modelData
                required property int index
                readonly property string pid: modelData.id
                readonly property bool allowed: AiPlanUsage.allowed(pid)
                readonly property var info: allowed ? AiPlanUsage.data[pid] : undefined
                readonly property bool ok: !!info && info.ok
                readonly property real mainPercent: AiPlanUsage.mainPercent(pid)
                Layout.fillWidth: true
                Layout.preferredWidth: 300
                spacing: 8

                Rectangle {
                    visible: provider.index > 0
                    Layout.fillWidth: true
                    Layout.bottomMargin: 2
                    implicitHeight: 1
                    color: Appearance.colors.colOutlineVariant
                }

                // Header: logo, name, plan, main percentage
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 3
                    spacing: 8

                    Rectangle {
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer
                        CustomIcon {
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            source: provider.modelData.icon
                            colorize: true
                            color: Appearance.colors.colPrimary
                        }
                    }

                    ColumnLayout {
                        spacing: -2
                        RowLayout {
                            spacing: 6
                            StyledText {
                                text: provider.modelData.name
                                font.weight: Font.Medium
                                font.pixelSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            Rectangle {
                                visible: provider.ok && !!provider.info.plan
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: planText.implicitWidth + 12
                                implicitHeight: planText.implicitHeight + 2
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colSecondaryContainer
                                StyledText {
                                    id: planText
                                    anchors.centerIn: parent
                                    text: root.planName(provider.info?.plan ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                        }
                        StyledText {
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnSurfaceVariant
                            opacity: 0.65
                            text: {
                                if (!provider.allowed) return Translation.tr("Online usage is off");
                                if (!provider.info) return Translation.tr("Loading…");
                                if (!provider.ok) return AiPlanUsage.errorText(provider.pid);
                                if (provider.info.limitReached) return Translation.tr("Limit reached");
                                return Translation.tr("Click to open %1").arg(provider.modelData.appName);
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        Layout.rightMargin: 6
                        visible: provider.ok && provider.mainPercent >= 0
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                        color: root.severityColor(provider.mainPercent)
                        text: `${Math.round(provider.mainPercent)}%`
                    }
                }

                // Off: explain how to turn it on
                StyledPopupValueRow {
                    visible: !provider.allowed
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    icon: "privacy_tip"
                    label: Translation.tr("Turn on in Settings › Bar › AI Usage")
                    value: ""
                }

                // One block per plan limit (Claude: 5-hour + weekly [+ per model]; Codex: plan windows)
                Repeater {
                    model: provider.ok ? (provider.info.limits ?? []) : []
                    delegate: ColumnLayout {
                        id: limit
                        required property var modelData
                        readonly property real percent: Math.max(0, Math.min(100, Number(modelData.percent) || 0))
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        spacing: 3

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            MaterialSymbol {
                                text: limit.modelData.key === "session" ? "schedule"
                                    : (/month/i.test(limit.modelData.subtitle ?? "") ? "calendar_month" : "date_range")
                                iconSize: Appearance.font.pixelSize.large
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                text: limit.modelData.title
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledText {
                                visible: !!limit.modelData.subtitle
                                text: `· ${limit.modelData.subtitle ?? ""}`
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: 0.6
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: `${Math.round(limit.percent)}%`
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                                color: root.severityColor(limit.percent)
                            }
                        }
                        StyledProgressBar {
                            Layout.fillWidth: true
                            valueBarWidth: 284
                            value: limit.percent / 100
                            highlightColor: root.severityColor(limit.percent)
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                text: AiPlanUsage.resetText(limit.modelData.resetsAt)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: 0.7
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                text: AiPlanUsage.resetDate(limit.modelData.resetsAt)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSurfaceVariant
                                opacity: 0.7
                            }
                        }
                    }
                }

                // Extra usage (Claude) / credits (Codex), only when the plan has it on
                StyledPopupValueRow {
                    readonly property var extra: provider.ok ? provider.info.extra : null
                    visible: !!extra && extra.enabled
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    icon: extra?.kind === "credits" ? "toll" : "payments"
                    label: extra?.kind === "credits" ? Translation.tr("Credits") : Translation.tr("Extra usage")
                    value: {
                        if (!extra) return "";
                        if (extra.unlimited) return Translation.tr("Unlimited");
                        if (extra.kind === "credits") return `${extra.balance ?? "0"}`;
                        const cur = extra.currency ? ` ${extra.currency}` : "";
                        return extra.limit != null ? `${Number(extra.spent ?? 0).toFixed(2)} / ${Number(extra.limit).toFixed(2)}${cur}`
                                                   : `${Number(extra.spent ?? 0).toFixed(2)}${cur}`;
                    }
                }

                // Claude Code sessions running on this PC (local)
                Repeater {
                    model: provider.pid === "claude" ? ClaudeUsage.sessions : []
                    delegate: StyledPopupValueRow {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        icon: modelData.status === "busy" ? "progress_activity" : "terminal"
                        label: modelData.name || Translation.tr("Session")
                        value: modelData.status === "busy" ? Translation.tr("Working") : Translation.tr("Idle")
                    }
                }
                StyledPopupValueRow {
                    visible: provider.pid === "claude" && ClaudeUsage.activeSessions === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    icon: "bedtime"
                    label: Translation.tr("No active Claude Code sessions")
                    value: ""
                }
            }
        }
    }
}
