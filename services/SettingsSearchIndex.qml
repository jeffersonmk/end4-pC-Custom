pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property var entriesByPage: ({})

    readonly property var labelledTypes: [
        "ConfigSwitch", "ConfigSpinBox", "ConfigTextArea", "ConfigSelectionArray",
        "ConfigComboBox", "ConfigSlider", "ConfigSelectionShapeArray", "ConfigRow",
        "ColorSelectionArray", "ContentSubsection", "ConfigTimeRow"
    ]

    // Each entry remembers the `visible:` conditions of the blocks around it, so options
    // that are hidden on the page (e.g. "Clock preset" when the clock isn't
    // Cookie) are also left out of the search results.
    function parsePage(source) {
        const typeOpen = /^\s*([A-Z][\w.]*)\s*\{/;
        const visibleProp = /^\s*visible:\s*(.+?)\s*;?\s*$/;
        const labelProp = /^\s*(title|text):\s*Translation\.tr\(\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')\s*\)/;
        const entries = [];
        const stack = [];  // frames: { type, visible }
        let section = "";
        let subsection = "";
        for (const line of source.split("\n")) {
            const prop = line.match(labelProp);
            const frame = stack.length > 0 ? stack[stack.length - 1] : null;
            const type = frame?.type ?? null;
            const vis = line.match(visibleProp);
            if (vis && frame && !line.includes("{")) frame.visible = vis[1];
            if (prop && type) {
                const label = (prop[2] ?? prop[3]).replace(/\\(["'])/g, "$1");
                if (type === "ContentSection" && prop[1] === "title") {
                    section = label;
                    subsection = "";
                    entries.push({ kind: "section", section: label, subsection: "", label: label, frames: stack.slice() });
                } else if (root.labelledTypes.includes(type)) {
                    entries.push({ kind: "option", section: section, subsection: type === "ContentSubsection" ? "" : subsection, label: label, frames: stack.slice() });
                    if (type === "ContentSubsection") subsection = label;
                }
            }
            const opens = (line.match(/\{/g) || []).length;
            const closes = (line.match(/\}/g) || []).length;
            for (let i = 0; i < closes; i++) stack.pop();
            const typeMatch = line.match(typeOpen);
            for (let i = 0; i < opens; i++) stack.push({ type: i === 0 && typeMatch ? typeMatch[1] : null, visible: "" });
        }
        // Frames are filled in while parsing (visible: may come after the title), so
        // resolve the conditions only now
        for (const entry of entries) {
            entry.conditions = entry.frames.map(f => f.visible).filter(v => v.length > 0);
            delete entry.frames;
        }
        return entries;
    }

    // ---- visibility of an entry
    // Ids used in `visible:` conditions that aren't global singletons
    function clockStylePresent(styleName) {
        const clock = Config.options.background.widgets.clock;
        return (!clock.showOnlyWhenLocked && clock.style === styleName) || clock.styleLocked === styleName;
    }
    function conditionScope() {
        return {
            "Config": Config, "GlobalStates": GlobalStates, "Persistent": Persistent, "WM": WM,
            "Battery": Battery, "Presets": Presets, "Gamepad": Gamepad, "Hyprland": Hyprland,
            "settingsClock": {
                "cookiePresent": root.clockStylePresent("cookie"),
                "digitalPresent": root.clockStylePresent("digital"),
            },
        };
    }
    property var compiledConditions: ({})
    function conditionHolds(expr, scope) {
        let fn = root.compiledConditions[expr];
        if (fn === undefined) {
            try {
                const names = Object.keys(scope);
                fn = new Function(...names, `return (${expr});`);
            } catch (e) {
                fn = null;
            }
            root.compiledConditions[expr] = fn;
        }
        if (fn === null) return true;
        try {
            return Boolean(fn(...Object.keys(scope).map(k => scope[k])));
        } catch (e) {
            // Refers to something only the page knows (an id, a local property): keep the entry
            return true;
        }
    }
    function entryVisible(entry, scope) {
        for (const expr of (entry.conditions ?? [])) {
            if (!root.conditionHolds(expr, scope)) return false;
        }
        return true;
    }

    function indexPage(pageId, source) {
        const next = Object.assign({}, root.entriesByPage);
        next[pageId] = root.parsePage(source);
        root.entriesByPage = next;
    }

    function search(query, limit) {
        const tokens = query.toLowerCase().trim().split(/\s+/).filter(t => t.length > 0);
        if (tokens.length === 0) return [];

        const results = [];
        const scope = root.conditionScope();
        for (const page of SettingsPages.pages) {
            const pageName = page.name.toLowerCase();
            const pageScore = root.scoreText(pageName, tokens);
            if (pageScore > 0) {
                results.push({
                    pageId: page.id, pageName: page.name, icon: page.icon,
                    kind: "page", section: "", label: page.name, score: pageScore + 50
                });
            }
            for (const entry of (root.entriesByPage[page.id] ?? [])) {
                const label = Translation.tr(entry.label);
                const section = Translation.tr(entry.section);
                const haystack = (label + " " + entry.label + " " + section + " " + pageName).toLowerCase();
                if (!tokens.every(t => haystack.includes(t))) continue;
                if (!root.entryVisible(entry, scope)) continue;
                const labelScore = Math.max(
                    root.scoreText(label.toLowerCase(), tokens),
                    root.scoreText(entry.label.toLowerCase(), tokens)
                );
                results.push({
                    pageId: page.id, pageName: page.name, icon: page.icon,
                    kind: entry.kind, section: section, label: label, rawLabel: entry.label, rawSection: entry.section, subsection: Translation.tr(entry.subsection ?? ""), rawSubsection: entry.subsection ?? "",
                    score: labelScore + (entry.kind === "section" ? 10 : 0)
                });
            }
        }
        results.sort((a, b) => b.score - a.score);
        return results.slice(0, limit);
    }

    function scoreText(text, tokens) {
        let score = 0;
        for (const token of tokens) {
            const at = text.indexOf(token);
            if (at < 0) continue;
            if (text === token) score += 100;
            else if (at === 0) score += 60;
            else if (text[at - 1] === " ") score += 40;
            else score += 20;
        }
        return score;
    }

    Instantiator {
        model: SettingsPages.pages
        delegate: FileView {
            required property var modelData
            path: FileUtils.trimFileProtocol(Quickshell.shellPath(modelData.path))
            onLoaded: root.indexPage(modelData.id, text())
        }
    }
}
