pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Upgrades low-resolution cover art.
 *
 * Some players only expose a tiny thumbnail over MPRIS (Pear Desktop / YouTube Music
 * gives Chromium's 120x120 temp PNG, YouTube thumbnails come as small "=w120-h120"
 * links). `CoverArt.url(player)` returns a better URL when one is known, otherwise the
 * player's own URL, so callers can simply use it in place of `player.trackArtUrl`.
 *
 * Lookup order (cached per artist+album, or artist+title when there's no album):
 *   1. size parameters in Google/YouTube image URLs are rewritten to 1200px (instant)
 *   2. iTunes search (1000x1000 artwork)
 *   3. Deezer search (cover_xl)
 *   4. MusicBrainz + Cover Art Archive (1200px; good for indie/metal releases)
 * For YouTube / YouTube Music the album cover is preferred over the video thumbnail even
 * when the thumbnail isn't small; the (upscaled) thumbnail is the fallback.
 */
Singleton {
    id: root

    property bool enabled: Config.options.media.hdCovers ?? true
    property var cache: ({})      // key -> hd url ("" = nothing better found)
    property var pending: ({})    // key -> true while searching
    property int revision: 0      // bumped when the cache changes so bindings re-evaluate

    readonly property string script: `${Directories.scriptPath}/media/hd_cover.py`
    readonly property string lookupCacheDir: FileUtils.trimFileProtocol(`${Directories.cache}/hdcovers`)

    signal cleared()
    property bool clearing: false

    // Forget every HD cover found so far (lookup results + downloaded images).
    // Covers are searched and downloaded again the next time they are shown.
    function clearCache() {
        if (root.clearing) return;
        root.clearing = true;
        clearProc.running = true;
    }

    Process {
        id: clearProc
        command: ["bash", "-c", `rm -rf '${root.lookupCacheDir}' '${Directories.coverArt}'; mkdir -p '${Directories.coverArt}'`]
        onExited: {
            root.cache = ({});
            root.pending = ({});
            root.clearing = false;
            root.revision++;
            root.cleared();
        }
    }

    function keyFor(player) {
        const artist = (player?.trackArtist ?? "").trim().toLowerCase();
        const album = (player?.trackAlbum ?? "").trim().toLowerCase();
        const title = (player?.trackTitle ?? "").trim().toLowerCase();
        if (artist === "") return "";
        if (album !== "") return `${artist}\u001f${album}`;
        if (title !== "") return `${artist}\u001ftrack:${title}`;
        return "";
    }

    // Rewrite size parameters of known CDNs to a larger size
    function upscaleUrl(url) {
        if (!url) return "";
        // googleusercontent / ytimg: "=w120-h120-l90-rj" or "=s120"
        if (/googleusercontent\.com|ggpht\.com/.test(url))
            return url.replace(/=(w\d+-h\d+|s\d+)[^/?#]*$/, "=w1200-h1200-l90-rj");
        // Subsonic/Navidrome/Jellyfin servers (Feishin): ask for a bigger size
        if (/getCoverArt|\/Images\/Primary/.test(url) && /[?&](size|width|maxWidth|fillWidth)=\d+/.test(url))
            return url.replace(/([?&](?:size|width|maxWidth|fillWidth)=)\d+/g, (m, k) => k + "1000");
        // i.ytimg.com/vi/<id>/(default|mqdefault|hqdefault|sddefault).jpg
        if (/i\d?\.ytimg\.com\/vi/.test(url))
            return url.replace(/\/(default|mqdefault|hqdefault|sddefault)(\.jpg|\.webp)/, "/maxresdefault$2");
        return url;
    }

    function isLowRes(url) {
        if (!url) return true;
        // Chromium/Electron temp thumbnails are always 120px
        if (url.startsWith("file:///tmp/.org.chromium") || url.startsWith("file:///tmp/.com.google.Chrome")) return true;
        return /=(w|s)\d{1,3}(-h\d{1,3})?[^/]*$/.test(url) || /\/(default|mqdefault)\.jpg/.test(url);
    }

    // YouTube / YouTube Music: the art is a video thumbnail (16:9, gets cropped in the
    // square cover). Prefer the album cover whenever one can be found.
    function isVideo(player) {
        const pageUrl = player?.metadata?.["xesam:url"] ?? "";
        const art = player?.trackArtUrl ?? "";
        const id = `${player?.identity ?? ""} ${player?.desktopEntry ?? ""} ${player?.dbusName ?? ""}`.toLowerCase();
        return /youtube\.com|youtu\.be/.test(pageUrl)
            || /ytimg\.com|googleusercontent\.com/.test(art)
            || /firefox-mpris\//.test(art)          // Zen/Firefox thumbnails of the page media
            || id.includes("youtube-music") || id.includes("pear");
    }

    function url(player) {
        const _ = root.revision;
        const original = player?.trackArtUrl ?? "";
        if (!root.enabled || !player) return original;

        const video = root.isVideo(player);
        const upscaled = root.upscaleUrl(original);
        if (!video) {
            if (upscaled !== original) return upscaled;
            if (!root.isLowRes(original)) return original;
        }
        const fallback = upscaled || original;

        const key = root.keyFor(player);
        if (key === "") return fallback;
        if (key in root.cache) return root.cache[key] || fallback;
        root.lookup(key, player.trackArtist, player.trackAlbum ?? "", player.trackTitle ?? "");
        return fallback;
    }

    function lookup(key, artist, album, title) {
        if (root.pending[key]) return;
        root.pending[key] = true;
        const proc = lookupComponent.createObject(root, { key: key, command: ["python3", root.script, artist, album, title] });
        proc.running = true;
    }

    Component {
        id: lookupComponent
        Process {
            id: proc
            property string key
            stdout: StdioCollector { id: out }
            onExited: (code) => {
                const result = code === 0 ? out.text.trim() : "";
                const next = Object.assign({}, root.cache);
                next[proc.key] = result.startsWith("http") ? result : "";
                root.cache = next;
                delete root.pending[proc.key];
                root.revision++;
                proc.destroy();
            }
        }
    }
}
