pragma Singleton
pragma ComponentBehavior: Bound
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * A nice wrapper for default Pipewire audio sink and source.
 */
Singleton {
    id: root

    // Misc props
    property bool ready: root.sink?.ready ?? false
    property PwNode defaultSink: Pipewire.defaultAudioSink
    // Node whose volume/mute actually affect what you hear. EasyEffects' virtual sink ignores
    // its own volume (its monitor ports don't apply channel volumes), so when it is the default
    // sink the volume has to be set on the real device EasyEffects outputs to.
    readonly property PwNode sink: {
        const def = root.defaultSink;
        if (def?.name !== "easyeffects_sink" || root.easyEffectsOutputName.length === 0)
            return def;
        return Pipewire.nodes.values.find(n => n.name === root.easyEffectsOutputName && n.isSink && !n.isStream) ?? def;
    }
    property string easyEffectsOutputName: ""
    property PwNode source: Pipewire.defaultAudioSource
    readonly property real hardMaxValue: 2.00 // People keep joking about setting volume to 5172% so...
    property string audioTheme: Config.options.sounds.theme
    property real value: sink?.audio?.volume ?? 0
    
    function friendlyDeviceName(node) {
        return (node.nickname || node.description || Translation.tr("Unknown"));
    }
    function appNodeDisplayName(node) {
        return (node.properties["application.name"] || node.description || node.name)
    }

    // Lists
    function correctType(node, isSink) {
        return (node.isSink === isSink) && node.audio
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter((node) => { // Should be list<PwNode> but it breaks ScriptModel
            return root.correctType(node, isSink) && node.isStream
        })
    }
    // Wine/Proton games open several streams at once (one per audio API they use), and each
    // would get its own mixer row. Streams of the same process are shown as one app when that
    // process is a Wine one. Everything else (e.g. one stream per browser tab) stays separate.
    function isWineStream(node) {
        const p = node.properties;
        const text = `${p["application.process.binary"] ?? ""} ${p["application.name"] ?? ""}`.toLowerCase();
        return /wine|proton|preloader|\.exe/.test(text);
    }
    function appGroups(isSink) {
        const nodes = root.appNodes(isSink);
        const winePids = new Set();
        for (const node of nodes) {
            const pid = node.properties["application.process.id"];
            if (pid && root.isWineStream(node)) winePids.add(String(pid));
        }
        const groups = [];
        const byKey = {};
        for (const node of nodes) {
            const pid = String(node.properties["application.process.id"] ?? "");
            const key = winePids.has(pid) ? `pid:${pid}` : `node:${node.id}`;
            if (!byKey[key]) {
                byKey[key] = { key: key, nodes: [] };
                groups.push(byKey[key]);
            }
            byKey[key].nodes.push(node);
        }
        return groups;
    }
    readonly property list<string> outputAppGroupKeys: root.appGroups(true).map(g => g.key)
    readonly property list<string> inputAppGroupKeys: root.appGroups(false).map(g => g.key)
    function appGroupNodes(isSink, key) {
        return root.appGroups(isSink).find(g => g.key === key)?.nodes ?? [];
    }
    function devices(isSink) {
        return Pipewire.nodes.values.filter(node => {
            return root.correctType(node, isSink) && !node.isStream
        })
    }
    readonly property list<var> outputAppNodes: root.appNodes(true)
    readonly property list<var> inputAppNodes: root.appNodes(false)
    readonly property list<var> outputDevices: root.devices(true)
    readonly property list<var> inputDevices: root.devices(false)

    // Signals
    signal sinkProtectionTriggered(string reason);

    // Controls
    function toggleMute() {
        if (!Audio.sink?.audio) return;
        Audio.sink.audio.muted = !Audio.sink.audio.muted;
    }

    function toggleMicMute() {
        if (!Audio.source?.audio) return;
        Audio.source.audio.muted = !Audio.source.audio.muted;
    }

    function incrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.min(1, Math.round((currentVolume + step) * 100) / 100);
    }
    
    function decrementVolume() {
        if (!Audio.sink?.audio) return;
        const currentVolume = Audio.value;
        const step = currentVolume < 0.1 ? 0.01 : 0.02;
        Audio.sink.audio.volume = Math.max(0, Math.round((currentVolume - step) * 100) / 100);
    }

    function setDefaultSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

    function setDefaultSource(node) {
        Pipewire.preferredDefaultAudioSource = node;
    }

    // Internals
    // EasyEffects stores its chosen output device in its dconf-style rc file (native or flatpak).
    Instantiator {
        model: [
            `${Quickshell.env("HOME")}/.config/easyeffects/db/easyeffectsrc`,
            `${Quickshell.env("HOME")}/.var/app/com.github.wwmm.easyeffects/config/easyeffects/db/easyeffectsrc`
        ]
        delegate: FileView {
            required property string modelData
            path: modelData
            printErrors: false
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                const m = text().match(/^outputDevice=(.+)$/m);
                if (m && m[1].trim().length > 0) root.easyEffectsOutputName = m[1].trim();
            }
        }
    }

    PwObjectTracker {
        objects: [sink, source]
    }

    Connections { // Protection against sudden volume changes
        target: sink?.audio ?? null
        property bool lastReady: false
        property real lastVolume: 0
        function onVolumeChanged() {
            if (!Config.options.audio.protection.enable) return;
            const newVolume = sink.audio.volume;
            // when resuming from suspend, we should not write volume to avoid pipewire volume reset issues
            if (isNaN(newVolume) || newVolume === undefined || newVolume === null) {
                lastReady = false;
                lastVolume = 0;
                return;
            }
            if (!lastReady) {
                lastVolume = newVolume;
                lastReady = true;
                return;
            }
            const maxAllowedIncrease = Config.options.audio.protection.maxAllowedIncrease / 100; 
            const maxAllowed = Config.options.audio.protection.maxAllowed / 100;

            if (newVolume - lastVolume > maxAllowedIncrease) {
                sink.audio.volume = lastVolume;
                root.sinkProtectionTriggered(Translation.tr("Illegal increment"));
            } else if (newVolume > maxAllowed || newVolume > root.hardMaxValue) {
                root.sinkProtectionTriggered(Translation.tr("Exceeded max allowed"));
                sink.audio.volume = Math.min(lastVolume, maxAllowed);
            }
            lastVolume = sink.audio.volume;
        }
    }

    function playSystemSound(soundName) {
        const ogaPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.oga`;
        const oggPath = `/usr/share/sounds/${root.audioTheme}/stereo/${soundName}.ogg`;

        // Try playing .oga first
        let command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            ogaPath
        ];
        Quickshell.execDetached(command);

        // Also try playing .ogg (ffplay will just fail silently if file doesn't exist)
        command = [
            "ffplay",
            "-nodisp",
            "-autoexit",
            oggPath
        ];
        Quickshell.execDetached(command);
    }
}
