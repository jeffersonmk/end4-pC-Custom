pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Plan limits of the AI apps logged in on this PC (Claude Code and Codex / ChatGPT desktop),
 * for the bar's AI Usage widget. Same helper scripts and opt-in keys as the cheat sheet's
 * AI usage tab: a provider is only queried while `cheatsheet.aiUsage.<id>` is on, it is shown
 * in the bar, and at least one bar widget is using this service.
 */
Singleton {
    id: root

    property int consumers: 0
    property real now: Date.now()

    readonly property var providers: [
        {
            id: "claude", name: "Claude Code", icon: "claude-symbolic",
            showKey: "claudeEnabled", appName: Translation.tr("Claude"),
            desktopIds: ["com.anthropic.Claude", "claude-desktop"],
            commands: ["claude-desktop"],
            fallbackUrl: "https://claude.ai",
            loginHint: Translation.tr("Run `claude` once to log in")
        },
        {
            id: "chatgpt", name: "Codex", icon: "openai-symbolic",
            showKey: "codexEnabled", appName: Translation.tr("ChatGPT"),
            desktopIds: ["chatgpt", "com.openai.chatgpt", "chatgpt-desktop"],
            commands: ["chatgpt", "chatgpt-desktop"],
            fallbackUrl: "https://chatgpt.com/codex",
            loginHint: Translation.tr("Log in with `codex login` or the ChatGPT desktop app")
        }
    ]

    // Data per provider id: { ok, plan, limits: [...], extra, error, fetchedAt }
    property var data: ({})
    property var loading: ({})

    function provider(id) {
        return root.providers.find(p => p.id === id);
    }
    function shown(id) {
        const p = root.provider(id);
        return !!p && (Config.options.bar.aiUsage[p.showKey] ?? true);
    }
    function allowed(id) {
        return Config.options.cheatsheet.aiUsage[id] ?? false;
    }
    function allow(id) {
        Config.options.cheatsheet.aiUsage[id] = true;
        Qt.callLater(root.refresh);
    }

    // Main number in the bar: Claude's 5-hour session, Codex's first plan window
    function mainLimit(id) {
        const d = root.data[id];
        if (!d || !d.ok || !d.limits || d.limits.length === 0) return null;
        return d.limits.find(l => l.key === "session") ?? d.limits[0];
    }
    function mainPercent(id) {
        const l = root.mainLimit(id);
        return l ? Math.max(0, Math.min(100, Number(l.percent) || 0)) : -1;
    }

    function resetText(iso) {
        if (!iso) return "";
        const ms = Date.parse(iso) - root.now;
        if (isNaN(ms)) return "";
        if (ms <= 0) return Translation.tr("Resetting now");
        const mins = Math.floor(ms / 60000);
        const d = Math.floor(mins / 1440), h = Math.floor((mins % 1440) / 60), m = mins % 60;
        const span = d > 0 ? `${d}d ${h}h` : (h > 0 ? `${h}h ${m}m` : `${m}m`);
        return Translation.tr("Resets in %1").arg(span);
    }
    function resetDate(iso) {
        if (!iso) return "";
        const date = new Date(iso);
        if (isNaN(date.getTime())) return "";
        const sameDay = date.toDateString() === new Date(root.now).toDateString();
        const time = Qt.formatTime(date, Config.options.time.format);
        return sameDay ? time : `${Qt.formatDate(date, "ddd dd/MM")} ${time}`;
    }

    function errorText(id) {
        const d = root.data[id];
        if (!d || d.ok) return "";
        switch (d.error) {
        case "no_credentials": return root.provider(id).loginHint;
        case "api_key_login": return Translation.tr("API-key login has no plan limits");
        case "expired": return Translation.tr("Login expired, open the app to renew it");
        case "unauthorized": return Translation.tr("Login rejected, log in again");
        case "network": return Translation.tr("No connection");
        default: return Translation.tr("Couldn't read usage");
        }
    }

    function open(id) {
        const p = root.provider(id);
        if (!p) return;
        for (const desktopId of p.desktopIds) {
            const entry = DesktopEntries.byId(desktopId);
            if (entry) {
                entry.execute();
                return;
            }
        }
        // Desktop entries are scanned lazily and may not be loaded yet: try the same
        // ids through gtk-launch, then the app binaries, then the website
        Quickshell.execDetached(["bash", "-c", root.launchScript(p)]);
    }
    function launchScript(p) {
        const q = s => `'${StringUtils.shellSingleQuoteEscape(s)}'`;
        return `for id in ${p.desktopIds.map(q).join(" ")}; do gtk-launch "$id" >/dev/null 2>&1 && exit 0; done; `
            + `for c in ${p.commands.map(q).join(" ")}; do if command -v "$c" >/dev/null 2>&1; then setsid -f "$c" >/dev/null 2>&1; exit 0; fi; done; `
            + `xdg-open ${q(p.fallbackUrl)}`;
    }

    function refresh() {
        for (let i = 0; i < procs.count; i++) procs.objectAt(i).fetch();
    }

    Timer {
        interval: Math.max(60, Config.options.bar.aiUsage.updateInterval) * 1000
        repeat: true
        running: Config.ready && root.consumers > 0
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: 30000
        repeat: true
        running: root.consumers > 0
        onTriggered: root.now = Date.now()
    }

    Instantiator {
        id: procs
        model: root.providers
        delegate: Process {
            id: proc
            required property var modelData
            readonly property string pid: modelData.id
            function fetch() {
                if (proc.running || !root.allowed(proc.pid) || !root.shown(proc.pid)) return;
                const l = Object.assign({}, root.loading); l[proc.pid] = true; root.loading = l;
                proc.running = true;
            }
            command: ["python3", FileUtils.trimFileProtocol(`${Directories.scriptPath}/ai/${modelData.id}_usage.py`)]
            stdout: StdioCollector {
                onStreamFinished: {
                    let parsed;
                    try { parsed = JSON.parse(text); } catch (e) { parsed = { ok: false, error: "bad_response" }; }
                    const prev = root.data[proc.pid];
                    // Keep the last good numbers when a later request fails
                    if (!parsed.ok && prev && prev.ok) parsed = Object.assign({}, prev, { ok: true, staleError: parsed.error });
                    const d = Object.assign({}, root.data); d[proc.pid] = parsed; root.data = d;
                    const l = Object.assign({}, root.loading); l[proc.pid] = false; root.loading = l;
                    root.now = Date.now();
                }
            }
        }
    }

    Connections {
        target: Config.options.cheatsheet.aiUsage
        function onClaudeChanged() { Qt.callLater(root.refresh) }
        function onChatgptChanged() { Qt.callLater(root.refresh) }
    }
}
