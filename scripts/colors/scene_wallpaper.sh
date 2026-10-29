#!/usr/bin/env bash
# Wallpaper Engine "scene" wallpapers, played by linux-wallpaperengine
# (https://github.com/Almamu/linux-wallpaperengine, AUR: linux-wallpaperengine-git).
#
#   scene_wallpaper.sh start <project.json|project dir> [screenshot.jpg]
#       Plays the scene on every monitor. With a screenshot path, waits until the
#       first frames are rendered and saved there (used for the colour scheme).
#   scene_wallpaper.sh stop
#   scene_wallpaper.sh restart
#       Starts the current wallpaper again if it is a scene, so FPS/sound changes
#       made in Settings apply. Does nothing otherwise.
#   scene_wallpaper.sh is-scene <path>
#       Exit 0 when <path> is the project.json of a scene.
#
# FPS and sound come from background.liveWallpaper.sceneFps / sceneAudio in the
# shell config. The Wallpaper Engine assets are found automatically when the app
# is installed through Steam.

set -u

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
CONFIG="$XDG_CONFIG_HOME/illogical-impulse/config.json"
LOG="$XDG_CACHE_HOME/quickshell/linux-wallpaperengine.log"
# The launcher in /usr/bin execs the real binary, whose process name is cut to 15 chars
PROC_NAME="linux-wallpaper"
# Projects that failed to render (e.g. 3D scenes, which linux-wallpaperengine does
# not support yet). The selector marks them; a later successful start clears them.
FAILED_LIST="$XDG_CACHE_HOME/quickshell/scene-failed.txt"

mark_failed() {
    mkdir -p "$(dirname -- "$FAILED_LIST")"
    grep -qxF -- "$1" "$FAILED_LIST" 2>/dev/null || echo "$1" >> "$FAILED_LIST"
}

clear_failed() {
    [[ -f "$FAILED_LIST" ]] || return 0
    grep -vxF -- "$1" "$FAILED_LIST" > "$FAILED_LIST.tmp"
    mv -- "$FAILED_LIST.tmp" "$FAILED_LIST"
}

is_scene() {
    local file="$1"
    [[ "$(basename -- "$file")" == "project.json" && -f "$file" ]] || return 1
    [[ "$(jq -r '(.type // "") | ascii_downcase' "$file" 2>/dev/null)" == "scene" ]]
}

stop() {
    pkill -x "$PROC_NAME" 2>/dev/null || return 0
    for _ in $(seq 1 30); do
        pgrep -x "$PROC_NAME" >/dev/null || return 0
        sleep 0.1
    done
    pkill -9 -x "$PROC_NAME" 2>/dev/null
    return 0
}

start() {
    local target="$1" shot="${2:-}"
    local dir="$target"
    [[ -f "$target" ]] && dir="$(dirname -- "$target")"
    if [[ ! -f "$dir/project.json" ]]; then
        echo "Not a Wallpaper Engine project: $target" >&2
        return 1
    fi
    if ! command -v linux-wallpaperengine >/dev/null; then
        echo "linux-wallpaperengine is not installed" >&2
        return 127
    fi

    local fps=30 audio=false
    if [[ -f "$CONFIG" ]]; then
        fps="$(jq -r '.background.liveWallpaper.sceneFps // 30' "$CONFIG" 2>/dev/null)"
        audio="$(jq -r '.background.liveWallpaper.sceneAudio // false' "$CONFIG" 2>/dev/null)"
    fi
    [[ "$fps" =~ ^[0-9]+$ ]] && (( fps >= 5 && fps <= 240 )) || fps=30

    # "background" layer: below the shell's own background surface, which turns
    # transparent for live wallpapers (same place mpvpaper draws).
    local args=(--layer background --fps "$fps")
    if [[ "$audio" == "true" ]]; then args+=(--volume 15); else args+=(--silent); fi
    local monitor monitors=0
    while read -r monitor; do
        [[ -n "$monitor" ]] || continue
        args+=(--screen-root "$monitor" --scaling fill)
        monitors=$((monitors + 1))
    done < <(hyprctl monitors -j | jq -r '.[] | .name')
    if (( monitors == 0 )); then
        echo "No monitors found" >&2
        return 1
    fi
    if [[ -n "$shot" ]]; then
        rm -f -- "$shot"
        args+=(--screenshot "$shot")
    fi

    stop
    mkdir -p "$(dirname -- "$LOG")"
    setsid -f linux-wallpaperengine "${args[@]}" "$dir" >"$LOG" 2>&1 </dev/null

    [[ -n "$shot" ]] || return 0
    for _ in $(seq 1 150); do
        if [[ -s "$shot" ]]; then
            clear_failed "$dir"
            return 0
        fi
        pgrep -x "$PROC_NAME" >/dev/null || break
        sleep 0.1
    done
    stop
    mark_failed "$dir"
    echo "linux-wallpaperengine did not render the scene, see $LOG" >&2
    return 1
}

case "${1:-}" in
    start) shift; start "${1:?project path}" "${2:-}" ;;
    stop) stop ;;
    restart)
        current="$(jq -r '.background.wallpaperPath // ""' "$CONFIG" 2>/dev/null)"
        if is_scene "$current"; then start "$current"; fi
        ;;
    is-scene) shift; is_scene "${1:-}" ;;
    *) echo "usage: $0 start <project.json|dir> [screenshot] | stop | restart | is-scene <path>" >&2; exit 2 ;;
esac
