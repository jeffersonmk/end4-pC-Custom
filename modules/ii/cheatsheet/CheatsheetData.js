.pragma library

// Turns the keybind tree from HyprlandKeybinds into a list of categories:
// [{ name, icon, binds: [{ mods: ["CTRL", "SUPER"], key: "T", description }] }]
// How keys are shown is decided by displayParts(), driven by Config.options.cheatsheet.

const modOrder = ["CTRL", "SUPER", "SHIFT", "ALT"];

const keyNames = {
    "Return": "Enter",
    "Slash": "/",
    "Period": ".",
    "Comma": ",",
    "Minus": "Minus",
    "Equal": "Equal",
    "Hash": "1-0",
    "mouse:272": "LMB",
    "mouse:273": "RMB",
    "mouse:274": "MMB",
    "mouse:275": "Mouse back",
    "mouse:276": "Mouse fwd",
    "mouse_up": "Scroll ↓",
    "mouse_down": "Scroll ↑",
    "Scroll ↑/↓": "Scroll",
    "Page_↑/↓": "PgUp/PgDn",
};

// Same symbol sets as illogical-impulse's cheatsheet (needs a Nerd Font)
const macSymbols = {
    "Ctrl": "󰘴",
    "Alt": "󰘵",
    "Shift": "󰘶",
    "Space": "󱁐",
    "Tab": "↹",
    "Equal": "󰇼",
    "Minus": "",
    "Print": "",
    "BackSpace": "󰭜",
    "Delete": "⌦",
    "Return": "󰌑",
    "Period": ".",
    "Escape": "⎋"
};

const functionSymbols = {
    "F1": "󱊫",
    "F2": "󱊬",
    "F3": "󱊭",
    "F4": "󱊮",
    "F5": "󱊯",
    "F6": "󱊰",
    "F7": "󱊱",
    "F8": "󱊲",
    "F9": "󱊳",
    "F10": "󱊴",
    "F11": "󱊵",
    "F12": "󱊶"
};

const mouseSymbols = {
    "mouse_up": "󱕐",
    "mouse_down": "󱕑",
    "mouse:272": "L󰍽",
    "mouse:273": "R󰍽",
    "Scroll ↑/↓": "󱕒",
    "Page_↑/↓": "⇞/⇟"
};

const modNames = { "CTRL": "Ctrl", "SUPER": "Super", "SHIFT": "Shift", "ALT": "Alt" };

// Section/prefix name -> display name
const categoryAliases = {
    "App": "Apps",
    "Misc": "Misc",
    "Shell": "Shell",
};

const categoryIcons = {
    "Shell": "keyboard_command_key",
    "Apps": "apps",
    "Utilities": "build",
    "Screen": "fit_screen",
    "Media": "music_note",
    "Window": "select_window",
    "Workspace": "view_carousel",
    "Session": "logout",
    "Virtual machines": "computer",
    "Custom": "person",
};

function iconFor(name) {
    return categoryIcons[name] ?? "keyboard";
}

function normalizeMod(mod) {
    const m = mod.trim().toUpperCase();
    if (m === "CONTROL") return "CTRL";
    if (m === "SUPER_L" || m === "SUPER_R" || m === "MOD4" || m === "WIN") return "SUPER";
    return m;
}

function orderMods(mods) {
    const unique = [];
    for (const mod of mods) {
        const m = normalizeMod(mod);
        if (m.length > 0 && !unique.includes(m)) unique.push(m);
    }
    return unique.sort((a, b) => {
        const ia = modOrder.indexOf(a), ib = modOrder.indexOf(b);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
    });
}

function displayKey(key) {
    if (!key) return "";
    return keyNames[key] ?? key;
}

// Binds documented only as comments look like "bind = SUPER + SHIFT, ←/↑/→/↓,,"
function parseCommentBind(raw) {
    const body = raw.replace(/^\s*bind\w*\s*=\s*/, "");
    const parts = body.split(",").map(s => s.trim());
    let modPart = parts[0] ?? "";
    let key = parts[1] ?? "";
    if (key.length === 0) {
        const pieces = modPart.split("+").map(s => s.trim()).filter(s => s.length > 0);
        key = pieces.pop() ?? "";
        modPart = pieces.join("+");
    }
    const mods = modPart.split("+").map(s => s.trim()).filter(s => s.length > 0);
    return { mods: mods, key: key };
}

function splitCategory(comment) {
    const idx = comment.indexOf(":");
    if (idx <= 0 || idx > 24) return { prefix: "", text: comment };
    return { prefix: comment.slice(0, idx).trim(), text: comment.slice(idx + 1).trim() };
}

function build(trees) {
    const categories = [];
    const byName = {};
    const seen = {};

    function add(categoryName, mods, key, description) {
        if (!byName[categoryName]) {
            byName[categoryName] = { name: categoryName, icon: iconFor(categoryName), binds: [] };
            categories.push(byName[categoryName]);
        }
        const id = categoryName + "|" + mods.join("+") + "+" + key + "|" + description;
        if (seen[id]) return;
        seen[id] = true;
        byName[categoryName].binds.push({ mods: mods, key: key, description: description });
    }

    function walk(node, sectionName, fallbackCategory) {
        const name = (node?.name ?? "").trim();
        const section = name.length > 0 ? name : sectionName;
        for (const bind of (node?.keybinds ?? [])) {
            const comment = (bind.comment ?? "").trim();
            if (comment.length === 0) continue;
            // Auto-generated descriptions for undocumented binds (volume keys etc.)
            if (/^Execute\s*:/.test(comment)) continue;

            let mods = bind.mods ?? [];
            let key = bind.key ?? "";
            if (bind.dispatcher === "comment") {
                const parsed = parseCommentBind(key);
                mods = parsed.mods;
                key = parsed.key;
            }

            const split = splitCategory(comment);
            let category = section;
            if (!category || category.length === 0) category = split.prefix;
            if (!category || category.length === 0) category = fallbackCategory;
            category = categoryAliases[category] ?? category;

            const orderedMods = orderMods(mods);
            // A bind on SUPER_L alone is "tap Super"
            if (orderedMods.includes("SUPER") && /^SUPER_[LR]$/i.test(key)) key = "";
            if (orderedMods.length === 0 && key.length === 0) continue;

            add(category, orderedMods, key, split.text.length > 0 ? split.text : comment);
        }
        for (const child of (node?.children ?? [])) walk(child, section, fallbackCategory);
    }

    for (const entry of trees) walk(entry.tree, "", entry.fallbackCategory);
    return categories.filter(c => c.binds.length > 0);
}

// options: { superKey, useMacSymbol, useFnSymbol, useMouseSymbol }
// Returns the list of keycap labels, e.g. ["Ctrl", "SUPER", "T"].
// "SUPER" is left as a marker so the UI can draw the default icon when no superKey is set.
function displayParts(bind, options) {
    const opts = options ?? {};
    const parts = bind.mods.map(mod => {
        if (mod === "SUPER") return (opts.superKey ?? "").length > 0 ? opts.superKey : "SUPER";
        const name = modNames[mod] ?? mod;
        if (opts.useMacSymbol && macSymbols[name]) return macSymbols[name];
        return name;
    });
    if (bind.key.length > 0) {
        const key = bind.key;
        let shown = null;
        if (opts.useMouseSymbol && mouseSymbols[key]) shown = mouseSymbols[key];
        else if (opts.useFnSymbol && functionSymbols[key]) shown = functionSymbols[key];
        else if (opts.useMacSymbol && macSymbols[key]) shown = macSymbols[key];
        parts.push(shown ?? displayKey(key));
    }
    return parts;
}

function matches(bind, categoryName, query) {
    if (query.length === 0) return true;
    const q = query.toLowerCase();
    const keys = bind.mods.map(mod => modNames[mod] ?? mod).concat([displayKey(bind.key), bind.key]);
    return bind.description.toLowerCase().includes(q)
        || categoryName.toLowerCase().includes(q)
        || keys.join(" ").toLowerCase().includes(q);
}

// Greedy masonry: put each category into the currently shortest column
function distribute(categories, columnCount) {
    const columns = [];
    const heights = [];
    for (let i = 0; i < columnCount; i++) { columns.push([]); heights.push(0); }
    for (const category of categories) {
        let target = 0;
        for (let i = 1; i < columnCount; i++) if (heights[i] < heights[target]) target = i;
        columns[target].push(category);
        heights[target] += 3 + category.binds.length;
    }
    return columns;
}
