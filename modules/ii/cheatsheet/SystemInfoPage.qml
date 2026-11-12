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
 * "System" tab of the cheat sheet: PC specs plus live CPU/GPU/VRAM/RAM/disk
 * usage and temperatures. Data comes from scripts/hardware/hwinfo.py
 * (static specs once, live values every `interval` ms while visible).
 */
Item {
    id: root

    property bool active: true
    property int interval: 2000
    readonly property int historyLength: 45

    property var specs: null
    property var live: null
    property list<real> cpuHistory: []
    property list<real> gpuHistory: []

    implicitHeight: pageColumn.implicitHeight

    readonly property string scriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hardware/hwinfo.py`)
    // MEGA cloud card (MEGAcmd), shown once it's installed; polled only while this page is open
    readonly property bool showCloud: MegaCloud.installed
    onActiveChanged: active ? MegaCloud.consumers++ : MegaCloud.consumers--
    Component.onCompleted: if (active) MegaCloud.consumers++
    Component.onDestruction: if (active) MegaCloud.consumers--
    // Drive health (SMART via UDisks, no root): {block name: entry} from scripts/hardware/diskhealth.py
    property var healthByName: ({})
    property bool healthLoaded: false
    readonly property string healthScriptPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/hardware/diskhealth.py`)
    readonly property var gpuSpec: specs?.gpus?.[0] ?? null
    readonly property var gpuLive: live?.gpus?.[0] ?? null

    // ---- formatting helpers
    function gib(bytes, digits = 1) {
        return bytes == null ? "--" : (bytes / 1073741824).toFixed(digits);
    }
    function diskSize(bytes) { // vendor-style decimal units
        if (bytes == null) return "--";
        if (bytes >= 1e12) return `${(bytes / 1e12).toFixed(bytes >= 1e13 ? 0 : 1)} TB`;
        return `${Math.round(bytes / 1e9)} GB`;
    }
    function fsSize(bytes) {
        if (bytes == null) return "--";
        if (bytes >= 1099511627776) return `${(bytes / 1099511627776).toFixed(2)} TB`;
        return `${(bytes / 1073741824).toFixed(bytes >= 107374182400 ? 0 : 1)} GB`;
    }
    function temp(t) {
        return t == null ? "--" : `${Math.round(t)}°C`;
    }
    function tempColor(t, warn = 75, hot = 88) {
        if (t == null) return Appearance.colors.colPrimary;
        if (t >= hot) return Appearance.colors.colError;
        if (t >= warn) return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.5);
        return Appearance.colors.colPrimary;
    }
    function usageColor(fraction) {
        return fraction >= 0.9 ? Appearance.colors.colError : Appearance.colors.colPrimary;
    }
    function uptime(seconds) {
        if (seconds == null) return "--";
        const d = Math.floor(seconds / 86400), h = Math.floor(seconds % 86400 / 3600), m = Math.floor(seconds % 3600 / 60);
        return d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m`;
    }
    function healthColor(verdict) {
        if (verdict === "bad") return Appearance.colors.colError;
        if (verdict === "caution") return ColorUtils.mix(Appearance.colors.colError, Appearance.colors.colPrimary, 0.5);
        if (verdict === "good") return Appearance.colors.colPrimary;
        return Appearance.colors.colSubtext;
    }
    function healthIcon(verdict) {
        return verdict === "bad" ? "error" : verdict === "caution" ? "warning" : verdict === "good" ? "check_circle" : "help";
    }
    function healthLabel(verdict) {
        return verdict === "bad" ? Translation.tr("Bad") : verdict === "caution" ? Translation.tr("Caution")
            : verdict === "good" ? Translation.tr("Good") : Translation.tr("Unknown");
    }
    // Short phrase for why the verdict is not "good" (codes come from diskhealth.py reasons[])
    function reasonText(code) {
        switch (code) {
        case "failing": return Translation.tr("The drive reports it is failing");
        case "attr_failing": return Translation.tr("A SMART attribute is below its threshold");
        case "past_failure": return Translation.tr("A SMART attribute failed in the past");
        case "critical_warning": return Translation.tr("Critical warning from the drive");
        case "spare_low": return Translation.tr("Spare blocks are almost used up");
        case "wear": return Translation.tr("Little life left");
        case "media_errors": return Translation.tr("Media errors");
        case "temp_high": return Translation.tr("Running too hot");
        case "reallocated": return Translation.tr("Reallocated sectors");
        case "pending": return Translation.tr("Pending sectors");
        case "uncorrectable": return Translation.tr("Uncorrectable sectors");
        }
        return code;
    }
    // Label + plain-language hint for each metric row (codes come from diskhealth.py metrics[])
    function metricInfo(code) {
        switch (code) {
        case "critical_warning": return [Translation.tr("Critical warnings"), Translation.tr("Flags the drive raises itself when something is wrong. Should be 0.")];
        case "wear_used": return [Translation.tr("Wear used"), Translation.tr("How much of the rated endurance has been used. The drive keeps working past 100%, but it is no longer trusted.")];
        case "life_left": return [Translation.tr("Life left"), Translation.tr("Remaining endurance as reported by the SSD.")];
        case "spare": return [Translation.tr("Spare blocks"), Translation.tr("Reserve used to replace worn-out cells. Bad when it drops to the limit shown.")];
        case "media_errors": return [Translation.tr("Media errors"), Translation.tr("Data integrity errors found by the drive. Should be 0.")];
        case "temperature": return [Translation.tr("Temperature"), Translation.tr("Current temperature read from the drive.")];
        case "error_log": return [Translation.tr("Error log entries"), Translation.tr("Entries in the drive's own error log. Often harmless, mostly from rejected commands.")];
        case "unsafe_shutdowns": return [Translation.tr("Unexpected power loss"), Translation.tr("Times the power was cut without a clean shutdown. Informational.")];
        case "power_cycles": return [Translation.tr("Power cycles"), Translation.tr("Times the drive was switched on. Informational.")];
        case "reallocated": return [Translation.tr("Reallocated sectors"), Translation.tr("Bad sectors the drive replaced with spares. Should be 0; a growing number means the drive is dying.")];
        case "reallocated_events": return [Translation.tr("Reallocation events"), Translation.tr("How many times a sector was remapped. Informational.")];
        case "pending": return [Translation.tr("Pending sectors"), Translation.tr("Sectors waiting to be remapped because they could not be read. Should be 0.")];
        case "uncorrectable": return [Translation.tr("Uncorrectable sectors"), Translation.tr("Sectors that could not be read or fixed. Should be 0.")];
        case "crc_errors": return [Translation.tr("Cable CRC errors"), Translation.tr("Transfer errors between drive and board, usually a cable or connector. Old counts do not go away.")];
        }
        return [code, ""];
    }
    function metricValue(m) {
        if (m.value == null) return "--";
        if (m.unit === "C") return root.temp(m.value);
        if (m.unit === "%") return `${m.value}%`;
        return String(m.value);
    }
    function metricLevelIcon(level) {
        return level === "bad" ? "error" : level === "caution" ? "warning" : level === "ok" ? "check_circle" : "info";
    }
    function metricLevelColor(level) {
        return level === "info" ? Appearance.colors.colSubtext : root.healthColor(level === "ok" ? "good" : level);
    }
    function hoursText(h) {
        if (h == null) return "--";
        return h >= 24 * 365 * 2 ? Translation.tr("%1 years powered on").arg((h / 8760).toFixed(1))
            : Translation.tr("%1 h powered on").arg(h);
    }
    function writtenText(bytes) {
        if (bytes == null) return "--";
        const tb = bytes / 1e12;
        return Translation.tr("%1 written").arg(tb >= 1 ? `${tb.toFixed(tb >= 100 ? 0 : 1)} TB` : `${Math.round(bytes / 1e9)} GB`);
    }
    function agoText(epoch) {
        if (!epoch) return "--";
        const m = Math.max(0, Math.round((Date.now() / 1000 - epoch) / 60));
        return m < 1 ? Translation.tr("just now") : m < 90 ? Translation.tr("%1 min ago").arg(m) : Translation.tr("%1 h ago").arg(Math.round(m / 60));
    }
    function pushHistory(list, value) {
        const next = list.concat([Math.max(0, Math.min(1, value))]);
        return next.length > historyLength ? next.slice(next.length - historyLength) : next;
    }

    // ---- data
    Process {
        id: staticProc
        running: true
        command: ["python3", root.scriptPath, "static"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.specs = JSON.parse(text); } catch (e) { console.warn("[Cheatsheet/System] static:", e); }
            }
        }
    }
    Process {
        id: liveProc
        command: ["python3", root.scriptPath, "live"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.live = data;
                    if (data.cpu?.usage != null) root.cpuHistory = root.pushHistory(root.cpuHistory, data.cpu.usage / 100);
                    const g = data.gpus?.[0];
                    if (g?.busy != null) root.gpuHistory = root.pushHistory(root.gpuHistory, g.busy / 100);
                } catch (e) { console.warn("[Cheatsheet/System] live:", e); }
            }
        }
    }
    Timer {
        running: root.active
        repeat: true
        triggeredOnStart: true
        interval: root.interval
        onTriggered: if (!liveProc.running) liveProc.running = true
    }
    Process {
        id: healthProc
        command: ["python3", root.healthScriptPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const map = {};
                    for (const d of JSON.parse(text).drives ?? []) map[d.name] = d;
                    root.healthByName = map;
                } catch (e) { console.warn("[Cheatsheet/System] health:", e); }
                root.healthLoaded = true;
            }
        }
    }
    // SMART values change slowly (UDisks refreshes them every few minutes): once a minute is plenty
    Timer {
        running: root.active
        repeat: true
        triggeredOnStart: true
        interval: 60000
        onTriggered: if (!healthProc.running) healthProc.running = true
    }

    // ---- layout
    ColumnLayout {
        id: pageColumn
        width: parent.width
        spacing: 10

        // Overview chips
        Flow {
            Layout.fillWidth: true
            spacing: 8
            InfoChip { icon: "computer"; text: root.specs?.hostname ?? "--" }
            InfoChip { icon: "deployed_code"; text: root.specs?.os ?? "--" }
            InfoChip { icon: "terminal"; text: root.specs ? `Linux ${root.specs.kernel}` : "--" }
            InfoChip { icon: "developer_board"; text: root.specs?.board ?? "--" }
            InfoChip { icon: "schedule"; text: Translation.tr("Up %1").arg(root.uptime(root.live?.uptime)) }
        }

        // CPU · GPU · Memory
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // CPU
            SectionCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                icon: "memory"
                title: "CPU"
                subtitle: root.specs?.cpu?.model ?? "--"
                details: {
                    const c = root.specs?.cpu;
                    if (!c) return "";
                    const parts = [c.cores ? Translation.tr("%1 cores · %2 threads").arg(c.cores).arg(c.threads)
                                           : Translation.tr("%1 threads").arg(c.threads)];
                    if (c.maxGhz) parts.push(Translation.tr("up to %1 GHz").arg(c.maxGhz));
                    if (c.l3) parts.push(`L3 ${c.l3.replace(/\s*\(.*\)/, "")}`);
                    return parts.join(" · ");
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Gauge {
                        label: Translation.tr("Usage")
                        fraction: (root.live?.cpu?.usage ?? 0) / 100
                        valueText: root.live?.cpu?.usage != null ? `${Math.round(root.live.cpu.usage)}%` : "--"
                        progressColor: root.usageColor(fraction)
                    }
                    Gauge {
                        label: Translation.tr("Temperature")
                        fraction: (root.live?.cpu?.temp ?? 0) / 100
                        valueText: root.temp(root.live?.cpu?.temp)
                        progressColor: root.tempColor(root.live?.cpu?.temp)
                    }
                    Gauge {
                        label: Translation.tr("Clock")
                        fraction: root.specs?.cpu?.maxGhz ? (root.live?.cpu?.freqGhz ?? 0) / root.specs.cpu.maxGhz : 0
                        valueText: root.live?.cpu?.freqGhz != null ? `${root.live.cpu.freqGhz.toFixed(1)}` : "--"
                        unit: "GHz"
                    }
                }
                HistoryGraph {
                    values: root.cpuHistory
                    label: Translation.tr("CPU usage")
                }
            }

            // GPU
            SectionCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                icon: "videogame_asset"
                title: "GPU"
                subtitle: root.gpuSpec?.name ?? Translation.tr("No GPU detected")
                details: {
                    const g = root.gpuSpec;
                    if (!g) return "";
                    const parts = [];
                    if (g.vramTotal) parts.push(Translation.tr("%1 GB VRAM").arg(Math.round(g.vramTotal / 1073741824)));
                    if (g.driver) parts.push(g.driver);
                    if (g.vbios) parts.push(`VBIOS ${g.vbios}`);
                    return parts.join(" · ");
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Gauge {
                        label: Translation.tr("Usage")
                        fraction: (root.gpuLive?.busy ?? 0) / 100
                        valueText: root.gpuLive?.busy != null ? `${Math.round(root.gpuLive.busy)}%` : "--"
                        progressColor: root.usageColor(fraction)
                    }
                    Gauge {
                        label: Translation.tr("Temperature")
                        fraction: (root.gpuLive?.temp ?? 0) / 100
                        valueText: root.temp(root.gpuLive?.temp)
                        progressColor: root.tempColor(root.gpuLive?.temp, 80, 95)
                        sublabel: root.gpuLive?.tempHotspot != null ? Translation.tr("Hotspot %1").arg(root.temp(root.gpuLive.tempHotspot)) : ""
                    }
                    Gauge {
                        label: "VRAM"
                        fraction: root.gpuLive?.vramTotal ? (root.gpuLive.vramUsed ?? 0) / root.gpuLive.vramTotal : 0
                        valueText: root.gpuLive?.vramUsed != null ? root.gib(root.gpuLive.vramUsed) : "--"
                        unit: root.gpuLive?.vramTotal ? `/ ${root.gib(root.gpuLive.vramTotal, 0)} GB` : ""
                        progressColor: root.usageColor(fraction)
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    MiniStat { visible: root.gpuLive?.power != null; icon: "bolt"; text: `${root.gpuLive?.power ?? 0} W` }
                    MiniStat { visible: root.gpuLive?.clockMhz != null; icon: "speed"; text: `${root.gpuLive?.clockMhz ?? 0} MHz` }
                    MiniStat { visible: root.gpuLive?.tempMem != null; icon: "thermostat"; text: Translation.tr("VRAM %1").arg(root.temp(root.gpuLive?.tempMem)) }
                    MiniStat {
                        visible: root.gpuLive?.fanRpm != null || root.gpuLive?.fanPercent != null
                        icon: "mode_fan"
                        text: root.gpuLive?.fanPercent != null ? `${root.gpuLive.fanPercent}%`
                            : (root.gpuLive?.fanRpm === 0 ? Translation.tr("Fan stopped") : `${root.gpuLive?.fanRpm ?? 0} RPM`)
                    }
                }
                HistoryGraph {
                    values: root.gpuHistory
                    label: Translation.tr("GPU usage")
                }
            }

            // Memory
            SectionCard {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                icon: "memory_alt"
                title: Translation.tr("Memory")
                subtitle: root.specs?.ramTotal ? Translation.tr("%1 GB RAM").arg(root.gib(root.specs.ramTotal)) : "--"
                details: root.live?.ram?.swapTotal ? Translation.tr("%1 GB swap").arg(root.gib(root.live.ram.swapTotal)) : ""

                UsageBar {
                    label: "RAM"
                    used: root.live?.ram?.used ?? 0
                    total: root.live?.ram?.total ?? 0
                    valueText: `${root.gib(root.live?.ram?.used)} / ${root.gib(root.live?.ram?.total)} GB`
                }
                UsageBar {
                    visible: (root.live?.ram?.swapTotal ?? 0) > 0
                    label: "Swap"
                    used: root.live?.ram?.swapUsed ?? 0
                    total: root.live?.ram?.swapTotal ?? 0
                    valueText: `${root.gib(root.live?.ram?.swapUsed, 2)} / ${root.gib(root.live?.ram?.swapTotal)} GB`
                }
                UsageBar {
                    visible: (root.gpuLive?.vramTotal ?? 0) > 0
                    label: "VRAM"
                    used: root.gpuLive?.vramUsed ?? 0
                    total: root.gpuLive?.vramTotal ?? 0
                    valueText: `${root.gib(root.gpuLive?.vramUsed)} / ${root.gib(root.gpuLive?.vramTotal, 0)} GB`
                }
                Item { Layout.fillHeight: true }
            }
        }

        // Storage
        SectionCard {
            Layout.fillWidth: true
            icon: "hard_drive"
            title: Translation.tr("Storage")
            subtitle: {
                const d = root.specs?.drives ?? [];
                if (d.length === 0) return "--";
                const total = d.reduce((sum, x) => sum + (x.size || 0), 0);
                const local = Translation.tr("%1 drive(s) · %2 total").arg(d.length).arg(root.diskSize(total));
                return root.showCloud && MegaCloud.total > 0
                    ? `${local} · ${Translation.tr("MEGA %1").arg(root.fsSize(MegaCloud.total))}` : local;
            }

            GridLayout {
                Layout.fillWidth: true
                columns: Math.max(1, Math.min((root.live?.drives?.length ?? root.specs?.drives?.length ?? 1) + (root.showCloud ? 1 : 0), Math.floor(width / 380)))
                columnSpacing: 10
                rowSpacing: 10
                Repeater {
                    model: root.live?.drives ?? root.specs?.drives ?? []
                    delegate: DriveCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.alignment: Qt.AlignTop
                        drive: modelData
                    }
                }
                CloudCard {
                    visible: root.showCloud
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                }
            }
        }
    }

    // ---------------------------------------------------------------- components
    component InfoChip: Rectangle {
        id: chip
        property string icon
        property string text
        implicitHeight: 32
        implicitWidth: chipRow.implicitWidth + 24
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                iconSize: 17
                color: Appearance.colors.colPrimary
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.text
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }

    component SectionCard: Rectangle {
        id: card
        property string icon
        property string title
        property string subtitle
        property string details
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
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        StyledText {
                            text: card.title
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: card.subtitle
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.large
                        }
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
                spacing: 12
            }
        }
    }

    component Gauge: ColumnLayout {
        id: gauge
        property string label
        property string sublabel: ""
        property real fraction: 0
        property string valueText
        property string unit: ""
        property color progressColor: Appearance.colors.colPrimary
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 4

        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 104
            implicitHeight: 104
            CircularProgress {
                anchors.centerIn: parent
                implicitSize: 104
                lineWidth: 7
                value: Math.max(0, Math.min(1, gauge.fraction))
                colPrimary: gauge.progressColor
                colSecondary: Appearance.colors.colLayer2
                enableAnimation: true
                animationDuration: 600
            }
            Column {
                anchors.centerIn: parent
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: gauge.valueText
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.family: Appearance.font.family.numbers
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: gauge.unit.length > 0
                    text: gauge.unit
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: gauge.label
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.small
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: gauge.sublabel.length > 0 ? gauge.sublabel : " "
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    component MiniStat: Rectangle {
        id: stat
        property string icon
        property string text
        implicitHeight: 28
        implicitWidth: statRow.implicitWidth + 18
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer2
        Row {
            id: statRow
            anchors.centerIn: parent
            spacing: 5
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: stat.icon
                iconSize: 15
                color: Appearance.colors.colSubtext
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: stat.text
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    component HistoryGraph: Rectangle {
        id: hist
        property list<real> values
        property string label
        Layout.fillWidth: true
        implicitHeight: 64
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        clip: true
        Graph {
            anchors.fill: parent
            anchors.topMargin: 18
            values: hist.values
            points: root.historyLength
            alignment: Graph.Alignment.Right
            fillOpacity: 0.25
        }
        StyledText {
            anchors {
                top: parent.top
                left: parent.left
                topMargin: 5
                leftMargin: 10
            }
            text: hist.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    component UsageBar: ColumnLayout {
        id: bar
        property string label
        property string icon: ""
        property real used: 0
        property real total: 0
        property string valueText
        readonly property real fraction: total > 0 ? Math.max(0, Math.min(1, used / total)) : 0
        Layout.fillWidth: true
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialSymbol {
                visible: bar.icon.length > 0
                text: bar.icon
                iconSize: 16
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: bar.label
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.small
            }
            StyledText {
                text: bar.valueText
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
            }
            StyledText {
                text: `${Math.round(bar.fraction * 100)}%`
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
                height: parent.height
                width: Math.max(height, parent.width * bar.fraction)
                radius: height / 2
                color: root.usageColor(bar.fraction)
                Behavior on width {
                    NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    component CloudCard: Rectangle {
        id: cloudCard
        readonly property bool problem: MegaCloud.status === "error"
        implicitHeight: cloudColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: cloudColumn
            anchors {
                fill: parent
                margins: 12
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: MegaCloud.icon
                    iconSize: 22
                    color: cloudCard.problem ? Appearance.colors.colError : Appearance.colors.colPrimary
                    opacity: MegaCloud.loggedIn ? 1 : 0.5
                    SequentialAnimation on opacity {
                        running: MegaCloud.status === "syncing"
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: "MEGA"
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: [Translation.tr("Cloud"), MegaCloud.stateText,
                               MegaCloud.syncs.length > 0 ? Translation.tr("%1 synced folder(s)").arg(MegaCloud.syncs.length) : ""].filter(x => x).join(" · ")
                        elide: Text.ElideRight
                        color: cloudCard.problem ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                RippleButton {
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: MegaCloud.loggedIn ? MegaCloud.openMega() : MegaCloud.openLoginTerminal()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: MegaCloud.loggedIn ? "open_in_new" : "login"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledToolTip {
                        text: MegaCloud.loggedIn ? Translation.tr("Open MEGA") : Translation.tr("Log in (mega-login in a terminal)")
                    }
                }
            }

            UsageBar {
                visible: MegaCloud.loggedIn
                icon: "cloud"
                label: Translation.tr("Cloud drive")
                used: MegaCloud.used
                total: MegaCloud.total
                valueText: `${root.fsSize(MegaCloud.used)} / ${root.fsSize(MegaCloud.total)}`
            }

            Repeater {
                model: MegaCloud.syncs
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: modelData.error !== "" ? "sync_problem" : modelData.status === "Synced" ? "cloud_done" : "cloud_sync"
                        iconSize: 16
                        color: modelData.error !== "" ? Appearance.colors.colError : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: modelData.local.replace(/^\/home\/[^/]+/, "~")
                        elide: Text.ElideMiddle
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    StyledText {
                        text: modelData.error !== "" ? modelData.error : modelData.run === "Running" ? modelData.status : modelData.run
                        color: modelData.error !== "" ? Appearance.colors.colError : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            RowLayout {
                visible: MegaCloud.uploads > 0 || MegaCloud.downloads > 0
                spacing: 6
                MaterialSymbol {
                    text: "swap_vert"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: Translation.tr("Transfers: %1 up, %2 down").arg(MegaCloud.uploads).arg(MegaCloud.downloads)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    component DriveCard: Rectangle {
        id: driveCard
        property var drive
        readonly property var health: root.healthByName[driveCard.drive?.name] ?? null
        implicitHeight: driveColumn.implicitHeight + 24
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: driveColumn
            anchors {
                fill: parent
                margins: 12
            }
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: (driveCard.drive?.kind ?? "").includes("HDD") ? "hard_drive" : (driveCard.drive?.kind ?? "").includes("NVMe") ? "memory" : "save"
                    iconSize: 22
                    color: Appearance.colors.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: driveCard.drive?.model ?? "--"
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer1
                        font.pixelSize: Appearance.font.pixelSize.normal
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: [driveCard.drive?.kind, root.diskSize(driveCard.drive?.size), `/dev/${driveCard.drive?.name}`].filter(x => x).join(" · ")
                        elide: Text.ElideRight
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                MiniStat {
                    readonly property var shownTemp: driveCard.drive?.temp ?? driveCard.health?.temp ?? null
                    visible: shownTemp != null
                    icon: "thermostat"
                    text: root.temp(shownTemp)
                    color: Appearance.colors.colLayer1
                }
            }

            DiskHealth {
                visible: root.healthLoaded
                info: driveCard.health
            }

            Repeater {
                model: driveCard.drive?.filesystems ?? []
                delegate: UsageBar {
                    required property var modelData
                    icon: "folder"
                    label: `${modelData.mount}  ·  ${modelData.fstype}`
                    used: modelData.used
                    total: modelData.size
                    valueText: `${root.fsSize(modelData.used)} / ${root.fsSize(modelData.size)}`
                }
            }

            RowLayout {
                visible: driveCard.drive?.filesystems !== undefined && (driveCard.drive?.filesystems?.length ?? 0) === 0
                spacing: 6
                MaterialSymbol {
                    text: driveCard.drive?.locked ? "lock" : "block"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    text: driveCard.drive?.locked ? Translation.tr("Encrypted, not unlocked (usage unavailable)") : Translation.tr("Not mounted")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
    }

    // SMART health block of a drive card: verdict badge, life bar, key numbers and an expandable list
    component DiskHealth: ColumnLayout {
        id: dh
        property var info
        property bool expanded: false
        readonly property bool available: info != null && info.supported === true
        readonly property string verdict: available ? info.verdict : "unknown"
        readonly property color accent: root.healthColor(verdict)
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                implicitHeight: 28
                implicitWidth: badgeRow.implicitWidth + 18
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(dh.accent, 0.82)
                Row {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 5
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.healthIcon(dh.verdict)
                        fill: 1
                        iconSize: 16
                        color: dh.accent
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dh.available ? Translation.tr("Health: %1").arg(root.healthLabel(dh.verdict)) : Translation.tr("SMART not available")
                        color: dh.accent
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: dh.available && (dh.info.reasons?.length ?? 0) > 0
                text: (dh.info?.reasons ?? []).map(r => root.reasonText(r.code)).join(" · ")
                elide: Text.ElideRight
                color: dh.accent
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            Item { Layout.fillWidth: true; visible: !(dh.available && (dh.info.reasons?.length ?? 0) > 0) }
            MouseArea {
                visible: dh.available
                implicitWidth: chevronRow.implicitWidth
                implicitHeight: 28
                cursorShape: Qt.PointingHandCursor
                onClicked: dh.expanded = !dh.expanded
                Row {
                    id: chevronRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Details")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: dh.expanded ? "expand_less" : "expand_more"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }

        // Remaining life bar (only when the drive reports it)
        ColumnLayout {
            visible: dh.available && dh.info.health != null
            Layout.fillWidth: true
            spacing: 5
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: "favorite"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Life left")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                StyledText {
                    text: `${dh.info?.health ?? 0}%`
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
                    height: parent.height
                    width: Math.max(height, parent.width * (dh.info?.health ?? 0) / 100)
                    radius: height / 2
                    color: dh.accent
                    Behavior on width {
                        NumberAnimation { duration: 500; easing.type: Easing.OutCubic }
                    }
                }
            }
        }

        Flow {
            visible: dh.available
            Layout.fillWidth: true
            spacing: 6
            MiniStat {
                visible: dh.info?.power_on_hours != null
                icon: "schedule"
                text: root.hoursText(dh.info?.power_on_hours)
                color: Appearance.colors.colLayer1
            }
            MiniStat {
                visible: dh.info?.written != null
                icon: "edit"
                text: root.writtenText(dh.info?.written)
                color: Appearance.colors.colLayer1
            }
        }

        // Expanded details: one row per SMART metric with a plain-language hint
        ColumnLayout {
            visible: dh.available && dh.expanded
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: dh.available ? dh.info.metrics.filter(m => m.code !== "life_left") : []
                delegate: RowLayout {
                    id: metricRow
                    required property var modelData
                    readonly property var labels: root.metricInfo(modelData.code)
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignTop
                        text: root.metricLevelIcon(metricRow.modelData.level)
                        fill: 1
                        iconSize: 16
                        color: root.metricLevelColor(metricRow.modelData.level)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: metricRow.labels[0]
                            color: Appearance.colors.colOnLayer1
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: metricRow.labels[1].length > 0
                            text: metricRow.labels[1]
                            wrapMode: Text.WordWrap
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignTop
                        text: root.metricValue(metricRow.modelData)
                        color: metricRow.modelData.level === "ok" || metricRow.modelData.level === "info"
                            ? Appearance.colors.colOnLayer1 : root.metricLevelColor(metricRow.modelData.level)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Last SMART reading: %1 · read from UDisks, nothing is written to the drive").arg(root.agoText(dh.info?.updated))
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}
