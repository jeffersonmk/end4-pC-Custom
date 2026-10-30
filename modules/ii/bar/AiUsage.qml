import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

// AI Usage: plan usage % of Claude Code and Codex, each with its own logo.
// Hover shows every limit; clicking a logo opens that app (Claude / ChatGPT desktop).
MouseArea {
    id: root
    Component.onCompleted: AiPlanUsage.consumers++
    Component.onDestruction: AiPlanUsage.consumers--

    property color contentColor: Appearance.colors.colOnLayer1
    property bool contentColorOverridden: false
    property bool vertical: false
    readonly property var shownProviders: AiPlanUsage.providers.filter(p => AiPlanUsage.shown(p.id))

    visible: shownProviders.length > 0
    implicitWidth: shownProviders.length === 0 ? 0 : (vertical ? Appearance.sizes.verticalBarWidth : content.implicitWidth + 12)
    implicitHeight: shownProviders.length === 0 ? 0 : (vertical ? content.implicitHeight + 10 : Appearance.sizes.barHeight)
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor

    // Provider under the click: the logo whose center is closest along the bar axis (no dead zones)
    function providerAt(x, y) {
        let best = "", bestDist = Infinity;
        for (let i = 0; i < repeater.count; i++) {
            const item = repeater.itemAt(i);
            if (!item) continue;
            const c = item.mapToItem(root, item.width / 2, item.height / 2);
            const dist = root.vertical ? Math.abs(y - c.y) : Math.abs(x - c.x);
            if (dist < bestDist) { bestDist = dist; best = item.modelData.id; }
        }
        return best;
    }

    onClicked: mouse => {
        if (Config.options.bar.tooltips.clickToShow) return; // click opens the popup in that mode
        const id = root.providerAt(mouse.x, mouse.y);
        if (id !== "") AiPlanUsage.open(id);
    }

    GridLayout {
        id: content
        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.shownProviders.length)
        columnSpacing: 10
        rowSpacing: 6

        Repeater {
            id: repeater
            model: root.shownProviders
            delegate: GridLayout {
                id: item
                required property var modelData
                readonly property real percent: AiPlanUsage.allowed(modelData.id) ? AiPlanUsage.mainPercent(modelData.id) : -1
                readonly property bool hasValue: percent >= 0
                readonly property color itemColor: {
                    if (!hasValue) return root.contentColorOverridden ? Qt.alpha(root.contentColor, 0.6) : Appearance.colors.colSubtext;
                    if (percent >= 90) return Appearance.colors.colError;
                    return root.contentColor;
                }
                columns: root.vertical ? 1 : 2
                columnSpacing: 4
                rowSpacing: 1

                CustomIcon {
                    Layout.alignment: Qt.AlignCenter
                    width: 15
                    height: 15
                    source: item.modelData.icon
                    colorize: true
                    color: item.itemColor
                }
                StyledText {
                    Layout.alignment: Qt.AlignCenter
                    text: item.hasValue ? `${Math.round(item.percent)}%` : "—"
                    font.pixelSize: root.vertical ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
                    font.features: { "tnum": 1 }
                    color: item.itemColor
                }
            }
        }
    }

    AiUsagePopup {
        hoverTarget: root
        providers: root.shownProviders
    }
}
