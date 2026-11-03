pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services.ai

/**
 * Basic service to handle LLM chats with LOCAL models only
 * (Ollama, vLLM, or extra models in config.ai.extraModels whose endpoint is local).
 * Online / API-key models were removed in this fork.
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    readonly property string interfaceRole: "interface"

    signal responseFinished()

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    // Only endpoints on this machine are accepted
    function isLocalEndpoint(endpoint) {
        return /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\]|0\.0\.0\.0)(:\d+)?(\/|$)/i.test(endpoint ?? "");
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})` 
    }

    // OpenAI-compatible function calling (Ollama / vLLM support it)
    // https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "functions"
    property var tools: {
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": {}
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools["openai"])

    // Function name -> the switch in Config.options.ai.functions
    readonly property var functionSwitch: ({
        "get_shell_config": "readConfig",
        "set_shell_config": "editConfig",
        "run_shell_command": "runCommands"
    })

    function isFunctionEnabled(name) {
        const key = root.functionSwitch[name];
        const f = Config?.options?.ai?.functions;
        if (!key || !f) return true;
        // The model must read the config before it edits it, so editing needs reading
        if (name === "set_shell_config" && !f.readConfig) return false;
        return f[key];
    }

    // Does the model accept tools? Unknown (vLLM, extra models, old Ollama) counts as yes.
    function modelSupportsTools(modelId) {
        const info = root.ollamaInfo[root.models[modelId]?.model ?? ""];
        if (!info || !info.capabilitiesKnown) return true;
        return info.capabilities.includes("tools");
    }
    readonly property bool currentModelSupportsTools: root.modelSupportsTools(root.currentModelId)

    readonly property int functionsTotal: Object.keys(root.functionSwitch).length
    readonly property int functionsEnabled: Object.keys(root.functionSwitch).filter(n => root.isFunctionEnabled(n)).length

    // Tools really sent to the model: none when it can't use them or they are switched off
    function effectiveTools() {
        if (!root.currentModelSupportsTools) return [];
        const list = root.tools["openai"][root.currentTool] ?? [];
        return list.filter(t => root.isFunctionEnabled(t.function.name));
    }
    property var toolDescriptions: {
        "functions": Translation.tr("Run commands and edit the shell config"),
        "search": Translation.tr("No effect on local models"),
        "none": Translation.tr("Disable tools")
    }

    // Model properties:
    // - name: Name of the model
    // - icon: Icon name of the model
    // - description: Description of the model
    // - endpoint: Endpoint of the model
    // - model: Model name of the model
    // - endpoint must be local (localhost / 127.0.0.1); OpenAI-compatible format
    // - extraParams: Extra parameters to be passed to the model. This is a JSON object.
    // Filled at runtime with local models (Ollama, vLLM, local extraModels)
    property var models: ({})
    property var modelList: Object.keys(root.models)
    // Embedding models (e.g. all-minilm) are installed for other tools and can't chat
    function isChatModel(modelId) {
        const info = root.ollamaInfo[root.models[modelId]?.model ?? ""];
        return !(info && info.capabilitiesKnown && info.capabilities.includes("embedding"));
    }
    property var currentModelId: {
        const saved = Persistent.states?.ai?.model;
        return (saved && models[saved]) ? saved : (modelList.find(id => root.isChatModel(id)) ?? "");
    }

    property ApiStrategy currentApiStrategy: openaiApiStrategy.createObject(this)

    function addUserModels() {
        (Config?.options.ai?.extraModels ?? []).forEach(model => {
            if (!root.isLocalEndpoint(model["endpoint"])) return; // online models are not supported
            const safeModelName = root.safeModelName(model["model"]);
            root.addModel(safeModelName, Object.assign({}, model, { "api_format": "openai", "requires_key": false }))
        });
        root.modelList = Object.keys(root.models);
    }

    Connections {
        target: Config
        function onReadyChanged() {
            if (!Config.ready) return;
            root.addUserModels()
            root.autostartOllamaIfWanted()
        }
    }

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string pendingFilePath: ""

    Component.onCompleted: {
        setModel(currentModelId, false, false); // Do necessary setup for model
        root.addUserModels() // Config onReadyChanged above might not fire if config is loaded before this service
    }

    function guessModelLogo(model) {
        const lower = model.toLowerCase();
        if (lower.includes("llama")) return "ollama-symbolic";
        if (lower.includes("gemma")) return "google-gemini-symbolic";
        if (lower.includes("deepseek")) return "deepseek-symbolic";
        if (lower.includes("mistral") || lower.includes("mixtral") || lower.includes("ministral") || lower.includes("codestral")) return "mistral-symbolic";
        if (lower.includes("qwen")) return "spark-symbolic";
        if (/^phi\d*:/i.test(model) || lower.includes("phi")) return "microsoft-symbolic";
        return "spark-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
    }

    // Details of the installed Ollama models (size, quantization, capabilities, loaded in
    // VRAM), keyed by the raw model name. Comes from scripts/ai/ollama-models.py, which
    // talks to the Ollama HTTP API (the same source /refresh uses to list the models).
    property var ollamaInfo: ({})
    property bool ollamaRunning: false
    property string ollamaVersion: ""
    property var ollamaModelIds: []
    readonly property string ollamaScript: `${Directories.scriptPath}/ai/ollama-models.py`.replace(/file:\/\//, "")

    Process {
        id: getOllamaModels
        running: true
        command: ["python3", root.ollamaScript, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text.trim().split("\n").pop());
                    root.applyOllamaList(data);
                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
    }

    function applyOllamaList(data) {
        root.ollamaRunning = data.running === true;
        root.ollamaVersion = data.version ?? "";
        const info = {};
        const next = Object.assign({}, root.models);
        // Drop the Ollama models of the previous scan so deleted ones disappear
        root.ollamaModelIds.forEach(id => delete next[id]);
        const ids = [];
        (data.models ?? []).forEach(m => {
            info[m.name] = m;
            const id = root.safeModelName(m.name);
            ids.push(id);
            next[id] = aiModelComponent.createObject(root, {
                "name": guessModelName(m.name),
                "icon": guessModelLogo(m.name),
                "description": Translation.tr("Local Ollama model | %1").arg(m.name),
                "homepage": `https://ollama.com/library/${m.name}`,
                "endpoint": "http://localhost:11434/v1/chat/completions",
                "model": m.name,
                "requires_key": false,
                "extraParams": {
                    "options": {
                        "num_ctx": Config?.options?.ai?.ollamaNumCtx ?? 32768
                    }
                }
            });
        });
        root.ollamaInfo = info;
        root.ollamaModelIds = ids;
        root.models = next;
        root.modelList = Object.keys(next);
    }

    Process {
        id: ollamaAction
        function run(action, name) {
            ollamaAction.exec(["python3", root.ollamaScript, action, name]);
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let ok = false;
                try { ok = JSON.parse(text.trim().split("\n").pop()).ok === true; } catch (e) {}
                if (!ok) root.addMessage(Translation.tr("The Ollama request failed. Is Ollama running?"), root.interfaceRole);
                root.refreshLocalModels();
            }
        }
    }

    // Free a model from VRAM/RAM right now (it stays installed)
    function unloadOllamaModel(name) { ollamaAction.run("unload", name); }
    // Remove a model from disk
    function deleteOllamaModel(name) { ollamaAction.run("delete", name); }

    Process {
        id: getVllmModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-running-vllm-models.sh "${Config?.options?.ai?.vllmEndpoint ?? "http://localhost:8000"}"`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    const vllmBase = (Config?.options?.ai?.vllmEndpoint ?? "http://localhost:8000").replace(/\/+$/, '');
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName("vllm-" + model);
                        const cleanModel = model.includes('/') ? model.split('/').pop() : model;
                        root.addModel(safeModelName, {
                            "name": `vLLM: ${guessModelName(cleanModel)}`,
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local vLLM model | %1").arg(model),
                            "homepage": "https://docs.vllm.ai",
                            "endpoint": `${vllmBase}/v1/chat/completions`,
                            "model": model,
                            "requires_key": false,
                        });
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch vLLM models:", e);
                }
            }
        }
    }


    // ---- Ollama server managed by the shell (scripts/ai/ollama-health.py) ----
    readonly property string healthScript: `${Directories.scriptPath}/ai/ollama-health.py`.replace(/file:\/\//, "")
    readonly property string ollamaDefaultDir: `${Quickshell.env("HOME")}/.ollama/models`
    readonly property string ollamaModelsDir: Config?.options?.ai?.ollama?.modelsDir || root.ollamaDefaultDir

    property var ollamaHealth: ({})      // status: running, owner, version, runners, devices, hint...
    property var ollamaDisks: []         // disks where the models can be stored
    property var ollamaFound: []         // folders that hold models ({path, models, bytes})
    property string ollamaBusy: ""       // "", "starting", "stopping", "moving"
    property real ollamaMoveProgress: 0
    property string ollamaMessage: ""    // last error, shown in the Ollama card
    property bool wantAutostart: false

    function refreshOllamaHealth() {
        if (healthProc.running) return;
        healthProc.running = true;
    }
    function refreshOllamaDisks() {
        if (!disksProc.running) disksProc.running = true;
        if (!scanProc.running) scanProc.running = true;
    }

    Process {
        id: healthProc
        command: ["python3", root.healthScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.ollamaHealth = JSON.parse(text.trim().split("\n").pop());
                } catch (e) {
                    console.log("Could not read the Ollama status:", e);
                }
                if (root.wantAutostart) {
                    root.wantAutostart = false;
                    if (root.ollamaHealth.installed && !root.ollamaHealth.running) root.startOllama();
                }
            }
        }
    }
    Process {
        id: disksProc
        command: ["python3", root.healthScript, "disks"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.ollamaDisks = JSON.parse(text.trim().split("\n").pop()).disks ?? []; } catch (e) {}
            }
        }
    }
    Process {
        id: scanProc
        command: ["python3", root.healthScript, "scan", root.ollamaModelsDir]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.ollamaFound = JSON.parse(text.trim().split("\n").pop()).found ?? []; } catch (e) {}
            }
        }
    }

    function ollamaErrorText(r) {
        switch (r.error) {
        case "not-installed": return Translation.tr("Ollama is not installed.");
        case "already-running": return r.owner === "system"
            ? Translation.tr("Ollama is already running as the system service. Stop it with `sudo systemctl stop ollama` to let the shell manage it.")
            : Translation.tr("Ollama is already running (not started by the shell).");
        case "disk-not-mounted": return Translation.tr("The disk %1 is not mounted. Unlock/mount it, then start Ollama again.").arg(r.mount ?? "");
        case "did-not-start": return Translation.tr("Ollama did not start. Check it with `journalctl --user -u shell-ollama`.");
        case "did-not-stop": return Translation.tr("Ollama did not stop in time.");
        case "not-owned": return Translation.tr("This Ollama was not started by the shell, so the shell won't stop it.");
        case "not-enough-space": return Translation.tr("Not enough free space on the new disk.");
        case "verify-failed": case "copy-failed": return Translation.tr("Copying the models failed. Nothing was deleted from the old folder.");
        case "ollama-running": return Translation.tr("Stop Ollama before moving the models.");
        case "rsync-missing": return Translation.tr("`rsync` is needed to move the models.");
        default: return Translation.tr("Ollama request failed: %1").arg(r.error ?? "?");
        }
    }

    // Small job queue: each step is { busy, args } (runs the helper) or { fn } (runs QML code)
    property var ollamaQueue: []
    property string ollamaLastLine: ""

    function runOllamaJob(steps) {
        if (root.ollamaBusy !== "") return;
        root.ollamaMessage = "";
        root.ollamaQueue = steps;
        root.nextOllamaStep();
    }

    function finishOllamaJob(message) {
        root.ollamaQueue = [];
        root.ollamaBusy = "";
        root.ollamaMessage = message ?? "";
        if ((message ?? "") !== "" && root.pullQueue.length > 0) {
            root.pullQueue.forEach(n => root.setPull(n, { state: "error", error: message }));
            root.pullQueue = [];
        }
        root.refreshLocalModels();
        root.refreshOllamaDisks();
        ollamaRecheck.restart(); // a status check that was already running may predate the change
    }

    Timer {
        id: ollamaRecheck
        interval: 1500
        onTriggered: root.refreshOllamaHealth()
    }

    function nextOllamaStep() {
        const q = root.ollamaQueue;
        if (q.length === 0) {
            root.finishOllamaJob("");
            return;
        }
        const step = q[0];
        root.ollamaQueue = q.slice(1);
        if (step.fn) {
            step.fn();
            root.nextOllamaStep();
            return;
        }
        root.ollamaBusy = step.busy;
        root.ollamaMoveProgress = 0;
        root.ollamaLastLine = "";
        ollamaJob.exec(["python3", root.healthScript, ...step.args]);
    }

    Process {
        id: ollamaJob
        stdout: SplitParser {
            onRead: line => {
                root.ollamaLastLine = line;
                try {
                    const r = JSON.parse(line);
                    if (r.phase === "copy" && r.percent !== undefined) root.ollamaMoveProgress = r.percent / 100;
                } catch (e) {}
            }
        }
        onExited: (exitCode, exitStatus) => {
            let r = { ok: false, error: "no-answer" };
            try { r = JSON.parse(root.ollamaLastLine); } catch (e) {}
            if (r.ok === true) root.nextOllamaStep();
            else root.finishOllamaJob(root.ollamaErrorText(r));
        }
    }

    function startOllama() {
        root.runOllamaJob([{
            busy: "starting",
            args: ["start", "--models-dir", root.ollamaModelsDir, "--require-mount", Config?.options?.ai?.ollama?.modelsMount ?? ""]
        }]);
    }

    function stopOllama() {
        root.runOllamaJob([{ busy: "stopping", args: ["stop"] }]);
    }

    function restartOllama() {
        root.runOllamaJob([
            { busy: "stopping", args: ["stop"] },
            { busy: "starting", args: ["start", "--models-dir", root.ollamaModelsDir, "--require-mount", Config?.options?.ai?.ollama?.modelsMount ?? ""] }
        ]);
    }

    // Store the models on another disk. Restarts Ollama if the shell runs it; optionally moves
    // the models already downloaded (copy, verify, then delete the old copy).
    function setModelsDisk(path, mount, moveExisting) {
        const h = root.ollamaHealth;
        if (h.running && h.owner !== "shell") {
            root.ollamaMessage = root.ollamaErrorText({ error: "already-running", owner: h.owner });
            return;
        }
        const wasRunning = h.running === true;
        const oldDir = root.ollamaModelsDir;
        const steps = [];
        if (wasRunning) steps.push({ busy: "stopping", args: ["stop"] });
        if (moveExisting) steps.push({ busy: "moving", args: ["move", oldDir, path] });
        steps.push({ fn: () => {
            Config.options.ai.ollama.modelsDir = path === root.ollamaDefaultDir ? "" : path;
            Config.options.ai.ollama.modelsMount = mount;
        } });
        if (wasRunning) steps.push({ busy: "starting", args: ["start", "--models-dir", path, "--require-mount", mount] });
        root.runOllamaJob(steps);
    }


    // ---- Model catalog (scripts/ai/ollama-catalog.py) and downloads (scripts/ai/ollama-pull.py) ----
    readonly property string catalogScript: `${Directories.scriptPath}/ai/ollama-catalog.py`.replace(/file:\/\//, "")
    readonly property string pullScript: `${Directories.scriptPath}/ai/ollama-pull.py`.replace(/file:\/\//, "")

    property var catalog: ({})            // { hardware, variants, source, fetchedAt, exactSizes }
    property bool catalogLoading: false
    property string catalogError: ""
    property int catalogCtx: Config?.options?.ai?.ollamaNumCtx ?? 32768
    property real refineDone: 0
    property real refineTotal: 0
    property bool refineRan: false

    // Free space of the disk that holds the models folder (-1 = not known yet)
    readonly property real modelsDiskFree: {
        const d = root.ollamaDisks.find(x => x.path === root.ollamaModelsDir);
        return d ? d.free : -1;
    }

    function loadCatalog(force) {
        if (catalogProc.running) return;
        root.catalogLoading = true;
        root.catalogError = "";
        const args = ["python3", root.catalogScript, "list", "--ctx", String(root.catalogCtx)];
        if (force) args.push("--refresh");
        catalogProc.exec(args);
    }

    function openCatalog() {
        root.loadCatalog(false);
        root.refreshOllamaHealth();
        root.refreshOllamaDisks();
        if (!root.refineRan) {
            root.refineRan = true;
            refineProc.exec(["python3", root.catalogScript, "refine"]);
        }
    }

    function setCatalogCtx(ctx) {
        root.catalogCtx = ctx;
        root.loadCatalog(false);
    }

    Process {
        id: catalogProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.catalogLoading = false;
                try {
                    const r = JSON.parse(text.trim().split("\n").pop());
                    if (r.ok) root.catalog = r;
                    else root.catalogError = Translation.tr("Could not load the model catalog.");
                } catch (e) {
                    root.catalogError = Translation.tr("Could not load the model catalog.");
                }
            }
        }
    }

    Process {
        id: refineProc
        stdout: SplitParser {
            onRead: line => {
                try {
                    const r = JSON.parse(line);
                    if (r.phase === "start" || r.phase === "refine") {
                        root.refineTotal = r.total;
                        root.refineDone = r.done ?? 0;
                    }
                } catch (e) {}
            }
        }
        onExited: {
            root.refineTotal = 0;
            root.loadCatalog(false); // now with the exact sizes
        }
    }

    // state per model name: "queued" | "pulling" | "done" | "error"
    property var pulls: ({})
    property var pullQueue: []
    property string pullActive: ""
    property bool pullCancelled: false
    property string pullLastLine: ""

    function setPull(name, patch) {
        const next = Object.assign({}, root.pulls);
        next[name] = Object.assign({}, next[name] ?? {}, patch);
        root.pulls = next;
    }
    function clearPull(name) {
        const next = Object.assign({}, root.pulls);
        delete next[name];
        root.pulls = next;
    }

    function pullModel(name, sizeGb) {
        const state = root.pulls[name]?.state;
        if (state === "queued" || state === "pulling") return;
        root.setPull(name, { state: "queued", percent: 0, completed: 0, total: 0, speed: 0, error: "", sizeBytes: Math.round(sizeGb * 1024 * 1024 * 1024) });
        root.pullQueue = [...root.pullQueue, name];
        root.drainPulls(false);
    }

    function cancelPull(name) {
        if (root.pullActive === name) {
            root.pullCancelled = true;
            pullProc.running = false; // Ollama keeps the partial files: pulling again resumes
        } else {
            root.pullQueue = root.pullQueue.filter(n => n !== name);
            root.clearPull(name);
        }
    }

    function drainPulls(serverReady) {
        if (root.pullActive !== "" || root.pullQueue.length === 0) return;
        if (!serverReady && root.ollamaHealth.running !== true) {
            if (root.ollamaBusy === "") {
                // Ollama is stopped: start it (the shell owns it), then go on
                root.runOllamaJob([
                    { busy: "starting", args: ["start", "--ok-if-running", "--models-dir", root.ollamaModelsDir, "--require-mount", Config?.options?.ai?.ollama?.modelsMount ?? ""] },
                    { fn: () => root.drainPulls(true) }
                ]);
            }
            return;
        }
        const name = root.pullQueue[0];
        root.pullQueue = root.pullQueue.slice(1);
        root.pullActive = name;
        root.pullCancelled = false;
        root.pullLastLine = "";
        root.setPull(name, { state: "pulling" });
        pullProc.exec(["python3", root.pullScript, name, "--models-dir", root.ollamaModelsDir, "--size-bytes", String(root.pulls[name].sizeBytes ?? 0)]);
    }

    function pullErrorText(r) {
        if (r.error === "no-space") return Translation.tr("Not enough free space on the models disk.");
        if (r.error === "interrupted" || (r.error ?? "").startsWith("connection")) return Translation.tr("The download was interrupted. Click again to resume it.");
        return Translation.tr("Download failed: %1").arg(r.error ?? "?");
    }

    Process {
        id: pullProc
        stdout: SplitParser {
            onRead: line => {
                root.pullLastLine = line;
                try {
                    const r = JSON.parse(line);
                    if (r.phase === "pull") root.setPull(root.pullActive, { percent: r.percent, completed: r.completed, total: r.total, speed: r.speed });
                } catch (e) {}
            }
        }
        onExited: (exitCode, exitStatus) => {
            const name = root.pullActive;
            let r = { ok: false, error: "interrupted" };
            try { r = JSON.parse(root.pullLastLine); } catch (e) {}
            root.pullActive = "";
            if (root.pullCancelled) root.clearPull(name);
            else if (r.ok === true) root.setPull(name, { state: "done", percent: 100 });
            else root.setPull(name, { state: "error", error: root.pullErrorText(r) });
            root.refreshLocalModels();
            root.refreshOllamaDisks();
            root.drainPulls(false);
        }
    }

    function autostartOllamaIfWanted() {
        if (!(Config?.options?.ai?.ollama?.autostart ?? false)) return;
        root.wantAutostart = true;
        root.refreshOllamaHealth();
    }

    function refreshLocalModels() {
        root.refreshOllamaHealth();
        getOllamaModels.running = false;
        getOllamaModels.running = true;
        getVllmModels.running = false;
        getVllmModels.running = true;
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    function addMessage(message, role, localFilePath = "") {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "localFilePath": localFilePath,
            "thinking": false,
            "done": true,
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
        return aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    // Shown when no local model is available yet
    readonly property var noModelPlaceholder: ({
        name: Translation.tr("No local model"),
        icon: "spark-symbolic",
        description: Translation.tr("Install Ollama and pull a model, then run /refresh"),
        endpoint: "",
        model: "",
    })

    function getModel() {
        return models[currentModelId] ?? root.noModelPlaceholder;
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        // Find the real model ID case-insensitively.
        const matchedModelId = modelList.find(id => id.toLowerCase() === modelId.toLowerCase())
        if (matchedModelId !== undefined) {
            modelId = matchedModelId
            if (!root.isChatModel(modelId)) {
                if (feedback) root.addMessage(Translation.tr("%1 is an embedding model and can't be used for chat.").arg(models[modelId].name), root.interfaceRole);
                return;
            }
            const model = models[modelId]
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
        } else {
            if (feedback) root.addMessage(Translation.tr("Invalid model. Supported: \n```\n") + modelList.join("\n```\n```\n"), Ai.interfaceRole) + "\n```"
        }
    }

    function setTool(tool) {
        if (!(tool in root.tools["openai"])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value, feedback = true) {
        if (isNaN(value) || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        if (feedback) root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages() {
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    FileView {
        id: requesterScriptFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null; // Reset hook after use
            }
            root.saveChat("lastSession")
            root.responseFinished()
        }

        function makeRequest() {
            const model = models[currentModelId];

            if (!model || !model.endpoint) {
                root.addMessage(Translation.tr("No local model available.\n\nInstall [Ollama](https://ollama.com), pull a model (e.g. `ollama pull llama3.2`) and run `/refresh`."), root.interfaceRole);
                return;
            }
            if (!root.isLocalEndpoint(model.endpoint)) {
                root.addMessage(Translation.tr("Only local models are supported"), root.interfaceRole);
                return;
            }

            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.effectiveTools(), root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);


            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);
            
            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        const attached = root.pendingFilePath;
        root.addMessage(message, "user", attached);
        requester.makeRequest();
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            // "visibleToUser": false,
        });
    }

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"

        const responseMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            requester.makeRequest(); // Continue
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (!root.isFunctionEnabled(name)) {
            // The model called something the user switched off (or never offered)
            addFunctionOutputMessage(name, Translation.tr("This function is turned off in the Functions menu."));
            return;
        }
        if (name === "switch_to_search_mode") {
            const modelId = root.currentModelId;
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
            })
        })
    }

    FileView {
        id: chatSaveFile
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        getSavedChats.running = true;
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages()
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                });
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            getSavedChats.running = true;
        }
    }
}
