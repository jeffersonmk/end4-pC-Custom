#!/usr/bin/env bash
set -u

APPS="$HOME/.local/share/applications"
DATA="$HOME/.local/share/shell-webapps"
ICONS="$DATA/icons"
PROFILES="$DATA/profiles"
PREFIX="shell-webapp-"
# Site icons are installed as named hicolor icons, so the icon theme can override them
HICOLOR="$HOME/.local/share/icons/hicolor"
ICON_HELPER="$(dirname "$(readlink -f "$0")")/webapp_icon.py"

current_icon_theme() {
    local theme="${WEBAPP_ICON_THEME:-}"
    [ -n "$theme" ] || theme="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null)"
    [ -n "$theme" ] || theme="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")"
    printf '%s\n' "${theme:-hicolor}"
}

# install_fallback_icon <png> <icon name>
install_fallback_icon() {
    mkdir -p "$HICOLOR/256x256/apps"
    [ -f "$HICOLOR/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$HICOLOR/index.theme" 2>/dev/null
    cp -f "$1" "$HICOLOR/256x256/apps/$2.png"
}

refresh_icon_caches() {
    [ -f "$HICOLOR/icon-theme.cache" ] && gtk-update-icon-cache -q -f -t "$HICOLOR" >/dev/null 2>&1
    command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1
    return 0
}

# themed_icon <fallback> <candidate>... -> theme icon name if the current theme has one, else fallback
themed_icon() {
    local fallback="$1" found; shift
    found="$(python3 "$ICON_HELPER" pick "$(current_icon_theme)" "$@" 2>/dev/null)"
    printf '%s\n' "${found:-$fallback}"
}

# Chromium-based browsers only (they support --app windows and --user-data-dir).
# "command|Display name", in automatic-selection order.
BROWSERS=(
    "chromium|Chromium" "google-chrome-stable|Google Chrome" "google-chrome|Google Chrome" "chrome|Google Chrome"
    "brave|Brave" "brave-browser|Brave" "helium-browser|Helium" "helium|Helium"
    "vivaldi-stable|Vivaldi" "vivaldi|Vivaldi" "microsoft-edge-stable|Microsoft Edge"
    "ungoogled-chromium|Ungoogled Chromium" "thorium-browser|Thorium"
)

# Installed browsers as JSON: [{id, name, path}]
list_browsers() {
    local entry cmd name path seen="" items="[]"
    for entry in "${BROWSERS[@]}"; do
        cmd="${entry%%|*}"; name="${entry#*|}"
        path="$(command -v "$cmd" 2>/dev/null)" || continue
        case " $seen " in *" $name "*) continue ;; esac
        seen="$seen $name"
        items="$(jq -c --arg id "$cmd" --arg name "$name" --arg path "$path" '. + [{id: $id, name: $name, path: $path}]' <<<"$items")"
    done
    printf '%s\n' "$items"
}

# find_browser [preferred command] -> prints "path|command"
find_browser() {
    local want="${1:-}" entry cmd path
    if [ -n "$want" ] && path="$(command -v "$want" 2>/dev/null)"; then
        printf '%s|%s\n' "$path" "$want"; return 0
    fi
    for entry in "${BROWSERS[@]}"; do
        cmd="${entry%%|*}"
        if path="$(command -v "$cmd" 2>/dev/null)"; then
            printf '%s|%s\n' "$path" "$cmd"; return 0
        fi
    done
    return 1
}

# Wayland app-id prefix used by each browser for --app windows
class_prefix() {
    case "$1" in
        brave*) echo brave ;;
        vivaldi*) echo vivaldi ;;
        microsoft-edge*) echo msedge ;;
        *) echo chrome ;;
    esac
}

normalize_url() {
    local url
    url="$(printf '%s' "$1" | tr -d '[:space:]')"
    [ -n "$url" ] || return 1
    case "$url" in
        http://*|https://*) ;;
        *) url="https://$url" ;;
    esac
    printf '%s' "$url"
}

parse_url() {
    python3 -I - "$1" <<'PY'
import sys, re
from urllib.parse import urlparse
url = sys.argv[1]
p = urlparse(url)
host = p.hostname or ""
if not host or "." not in host and host != "localhost":
    sys.exit(1)
path = p.path or "/"
bare = re.sub(r"^www\.", "", host)
slug = re.sub(r"[^a-z0-9]+", "-", (bare + path).lower()).strip("-")
parts = bare.split(".")
if bare == "localhost" or len(parts) < 2:
    label = parts[0]
elif len(parts) >= 3 and len(parts[-1]) == 2 and parts[-2] in ("co", "com", "org", "net", "gov", "edu", "ac"):
    label = parts[-3]
else:
    label = parts[-2]
print(slug)
print(label.capitalize())
print(host + "_" + path.replace("/", "_"))
PY
}

page_info() {
    python3 -I - "$1" <<'PY'
import sys, re, json
from urllib.request import Request, urlopen
from urllib.parse import urljoin

UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0 Safari/537.36"
base = sys.argv[1]

def get(url, limit=400000):
    req = Request(url, headers={"User-Agent": UA})
    with urlopen(req, timeout=10) as resp:
        return resp.geturl(), resp.read(limit)

def attrs(tag):
    return {k.lower(): v for k, _, v in re.findall(r'([\w:-]+)\s*=\s*(["\'])(.*?)\2', tag)}

name = ""
cands = []
try:
    final, raw = get(base)
    html = raw.decode("utf-8", "ignore")
    for tag in re.findall(r"<meta\b[^>]*>", html, re.I):
        a = attrs(tag)
        key = (a.get("property") or a.get("name") or "").lower()
        if key in ("og:site_name", "application-name") and a.get("content") and not name:
            name = a["content"].strip()
    manifest = None
    for tag in re.findall(r"<link\b[^>]*>", html, re.I):
        a = attrs(tag)
        rel = (a.get("rel") or "").lower()
        href = a.get("href")
        if not href:
            continue
        if "manifest" in rel:
            manifest = urljoin(final, href)
        elif "icon" in rel:
            size = 0
            m = re.match(r"(\d+)x\d+", (a.get("sizes") or "").split(" ")[0])
            if m:
                size = int(m.group(1))
            elif "apple-touch" in rel:
                size = 180
            cands.append((size, urljoin(final, href)))
    if manifest:
        try:
            murl, mraw = get(manifest, 200000)
            data = json.loads(mraw.decode("utf-8", "ignore"))
            name = name or data.get("short_name") or data.get("name") or ""
            for icon in data.get("icons", []):
                m = re.match(r"(\d+)x\d+", (icon.get("sizes") or "").split(" ")[0])
                cands.append((int(m.group(1)) if m else 0, urljoin(murl, icon.get("src", ""))))
        except Exception:
            pass
except Exception:
    pass

print(name)
seen = set()
for size, url in sorted(cands, key=lambda c: -c[0]):
    if url and url not in seen:
        seen.add(url)
        print(url)
PY
}

icon_ok() {
    local file="$1" width
    width="$(magick identify -quiet -format '%w\n' "$file" 2>/dev/null | sort -n | tail -n1)"
    [ -n "$width" ] && [ "$width" -ge "${2:-48}" ]
}

save_icon() {
    local src="$1" out="$2" frame
    frame="$(magick identify -quiet -format '%p %w\n' "$src" 2>/dev/null | sort -k2 -n | tail -n1 | cut -d' ' -f1)"
    magick "$src[${frame:-0}]" -background none -resize 256x256 "png:$out.part" 2>/dev/null && mv -f "$out.part" "$out"
}

fetch_icon() {
    local url="$1" host="$2" out="$3" tmp candidate bare
    mkdir -p "$ICONS"
    tmp="$out.src"
    bare="${host#www.}"
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if curl -sSL -f -m 12 -A "Mozilla/5.0" -o "$tmp" "$candidate" && icon_ok "$tmp" 96 && save_icon "$tmp" "$out"; then
            rm -f "$tmp"
            return 0
        fi
    done <<<"$PAGE_ICONS"
    for candidate in "$host" "$bare" "${bare#*.}"; do
        [ -n "$candidate" ] && [[ "$candidate" == *.* ]] || continue
        if curl -sSL -f -m 12 -o "$tmp" "https://t3.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&url=https://$candidate&size=256" \
            && icon_ok "$tmp" 32 && save_icon "$tmp" "$out"; then
            rm -f "$tmp"
            return 0
        fi
    done
    rm -f "$tmp" "$out.part"
    return 1
}

create_one() {
    local raw="$1" found browser bcmd url parsed slug name appid host icon file info site exec_line profile=""
    found="$(find_browser "${WEBAPP_BROWSER:-}")" || { echo "ERR no Chromium-based browser found"; return 1; }
    browser="${found%%|*}"; bcmd="${found#*|}"
    url="$(normalize_url "$raw")" || { echo "ERR empty url"; return 1; }
    parsed="$(parse_url "$url")" || { echo "ERR invalid url: $raw"; return 1; }
    slug="$(printf '%s\n' "$parsed" | sed -n 1p)"
    name="$(printf '%s\n' "$parsed" | sed -n 2p)"
    appid="$(printf '%s\n' "$parsed" | sed -n 3p)"
    host="$(python3 -I -c 'import sys;from urllib.parse import urlparse;print(urlparse(sys.argv[1]).hostname)' "$url")"
    file="$APPS/$PREFIX$slug.desktop"
    icon="$ICONS/$slug.png"
    info="$(page_info "$url")"
    site="$(printf '%s\n' "$info" | sed -n 1p)"
    PAGE_ICONS="$(printf '%s\n' "$info" | sed -n '2,$p')"
    [ -n "$site" ] && name="$site"
    # Site icon -> named fallback icon; the current icon theme wins when it has one
    local fallback="applications-internet" themed_names
    if fetch_icon "$url" "$host" "$icon"; then
        fallback="$PREFIX$slug"
        install_fallback_icon "$icon" "$fallback"
        rm -f "$icon"
    fi
    themed_names="$(python3 "$ICON_HELPER" candidates "$host" "$name" 2>/dev/null | paste -sd';')"
    # shellcheck disable=SC2086
    icon="$(IFS=';'; themed_icon "$fallback" $themed_names)"

    # Isolated: own browser profile (logins, cookies, extensions, cache), separate
    # from the main browser and from other webapps - like Linux Mint's webapp-manager
    exec_line="$browser --app=\"$url\""
    if [ "${WEBAPP_ISOLATED:-1}" = "1" ]; then
        profile="$PROFILES/$slug"
        mkdir -p "$profile"
        exec_line="$exec_line --user-data-dir=\"$profile\" --class=WebApp-$slug --no-first-run --no-default-browser-check"
    fi

    mkdir -p "$APPS"
    cat > "$file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$name
Exec=$exec_line
Icon=$icon
Terminal=false
Categories=Network;WebApps;
StartupWMClass=$(class_prefix "$bcmd")-$appid-Default
StartupNotify=true
X-Shell-Webapp=true
X-Shell-Webapp-Url=$url
X-Shell-Webapp-Browser=$bcmd
X-Shell-Webapp-Profile=$profile
X-Shell-Webapp-ThemeIcons=$themed_names
X-Shell-Webapp-FallbackIcon=$fallback
DESKTOP
    refresh_icon_caches
    echo "OK $slug"
}

list_all() {
    local file id name url icon browser profile items="[]"
    for file in "$APPS"/$PREFIX*.desktop; do
        [ -e "$file" ] || continue
        grep -q '^X-Shell-Webapp=true' "$file" || continue
        id="$(basename "$file" .desktop)"
        name="$(sed -n 's/^Name=//p' "$file" | head -n1)"
        url="$(sed -n 's/^X-Shell-Webapp-Url=//p' "$file" | head -n1)"
        icon="$(sed -n 's/^Icon=//p' "$file" | head -n1)"
        browser="$(sed -n 's/^X-Shell-Webapp-Browser=//p' "$file" | head -n1)"
        profile="$(sed -n 's/^X-Shell-Webapp-Profile=//p' "$file" | head -n1)"
        if [ -z "$browser" ]; then
            browser="$(sed -n 's/^Exec=//p' "$file" | head -n1 | cut -d' ' -f1)"; browser="${browser##*/}"
        fi
        items="$(jq -c --arg id "$id" --arg name "$name" --arg url "$url" --arg icon "$icon" --arg browser "$browser" --argjson isolated "$([ -n "$profile" ] && echo true || echo false)" \
            --argjson custom "$(grep -q '^X-Shell-Webapp-CustomIcon=' "$file" && echo true || echo false)" \
            '. + [{id: $id, name: $name, url: $url, icon: $icon, browser: $browser, isolated: $isolated, customIcon: $custom}]' <<<"$items")"
    done
    jq -c 'sort_by(.name | ascii_downcase)' <<<"$items"
}

remove_one() {
    local id="$1" file profile
    case "$id" in
        "$PREFIX"*) ;;
        *) echo "ERR not a shell webapp"; return 1 ;;
    esac
    file="$APPS/$id.desktop"
    [ -f "$file" ] && grep -q '^X-Shell-Webapp=true' "$file" || { echo "ERR not found"; return 1; }
    profile="$(sed -n 's/^X-Shell-Webapp-Profile=//p' "$file" | head -n1)"
    rm -f "$file" "$ICONS/${id#"$PREFIX"}.png" "$HICOLOR/256x256/apps/$id.png"
    remove_custom_icons "$id"
    # Delete the isolated profile too (only inside our profiles dir)
    case "$profile" in
        "$PROFILES"/?*) rm -rf -- "$profile" ;;
    esac
    echo "OK $id"
}

# rename_one <id> <new name>: change only the launcher's display name
rename_one() {
    local id="$1" name="$2" file tmp
    case "$id" in "$PREFIX"*) ;; *) echo "ERR not a shell webapp"; return 1 ;; esac
    file="$APPS/$id.desktop"
    [ -f "$file" ] && grep -q '^X-Shell-Webapp=true' "$file" || { echo "ERR not found"; return 1; }
    # One line, no control characters, trimmed, at most 80 characters
    name="$(printf '%s' "$name" | tr '\000-\037\177' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ | $//g')"
    name="${name:0:80}"
    [ -n "$name" ] || { echo "ERR empty name"; return 1; }
    tmp="$(mktemp "$file.XXXXXX")" || { echo "ERR could not write"; return 1; }
    NEW_NAME="$name" awk 'BEGIN { done = 0 }
        /^Name=/ && !done { print "Name=" ENVIRON["NEW_NAME"]; done = 1; next }
        { print }' "$file" > "$tmp" && cat "$tmp" > "$file" || { rm -f "$tmp"; echo "ERR could not write"; return 1; }
    rm -f "$tmp"   # (cat keeps the launcher's original permissions)
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APPS" >/dev/null 2>&1
    echo "OK $id"
}

# set_key <file> <key> <value>: replace the key's line, or append it (keeps permissions)
set_key() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp "$file.XXXXXX")" || return 1
    KEY="$key" VALUE="$value" awk 'BEGIN { done = 0 }
        index($0, ENVIRON["KEY"] "=") == 1 { if (!done) print ENVIRON["KEY"] "=" ENVIRON["VALUE"]; done = 1; next }
        { print }
        END { if (!done) print ENVIRON["KEY"] "=" ENVIRON["VALUE"] }' "$file" > "$tmp" && cat "$tmp" > "$file"
    local status=$?
    rm -f "$tmp"
    return "$status"
}

# Custom icon images installed by "seticon" (named <id>-custom-<time>, so caches never show an old one)
remove_custom_icons() {
    rm -f "$HICOLOR"/256x256/apps/"$1"-custom-*.png "$HICOLOR"/scalable/apps/"$1"-custom-*.svg
}

# seticon_one <id> <image file | theme icon name>: the user's own icon; kept across theme changes
seticon_one() {
    local id="$1" src="$2" file icon
    case "$id" in "$PREFIX"*) ;; *) echo "ERR not a shell webapp"; return 1 ;; esac
    file="$APPS/$id.desktop"
    [ -f "$file" ] && grep -q '^X-Shell-Webapp=true' "$file" || { echo "ERR not found"; return 1; }
    src="${src#file://}"
    [ -n "$src" ] || { echo "ERR no icon"; return 1; }
    if [ -f "$src" ]; then
        icon="$id-custom-$(date +%s)"
        mkdir -p "$HICOLOR"
        [ -f "$HICOLOR/index.theme" ] || cp /usr/share/icons/hicolor/index.theme "$HICOLOR/index.theme" 2>/dev/null
        case "${src,,}" in
            *.svg)
                remove_custom_icons "$id"
                mkdir -p "$HICOLOR/scalable/apps"
                cp -f "$src" "$HICOLOR/scalable/apps/$icon.svg" || { echo "ERR could not copy the image"; return 1; } ;;
            *)
                icon_ok "$src" 16 || { echo "ERR not an image"; return 1; }
                mkdir -p "$HICOLOR/256x256/apps"
                # Square canvas (centered, transparent) so wide/tall images aren't stretched
                save_icon "$src" "$HICOLOR/256x256/apps/$icon.png.new" \
                    && magick "$HICOLOR/256x256/apps/$icon.png.new" -background none -gravity center -extent 256x256 "png:$HICOLOR/256x256/apps/$icon.png.new" \
                    || { rm -f "$HICOLOR/256x256/apps/$icon.png.new"; echo "ERR could not convert the image"; return 1; }
                remove_custom_icons "$id"
                mv -f "$HICOLOR/256x256/apps/$icon.png.new" "$HICOLOR/256x256/apps/$icon.png" ;;
        esac
    elif [[ "$src" =~ ^[A-Za-z0-9._+-]+$ ]]; then
        icon="$src"   # icon from the current icon theme
        remove_custom_icons "$id"
    else
        echo "ERR file not found"; return 1
    fi
    set_key "$file" Icon "$icon" && set_key "$file" X-Shell-Webapp-CustomIcon "$icon" || { echo "ERR could not write"; return 1; }
    refresh_icon_caches
    echo "OK $id"
}

# reseticon_one <id>: back to the automatic icon (site icon / icon theme)
reseticon_one() {
    local id="$1" file fallback names icon tmp
    case "$id" in "$PREFIX"*) ;; *) echo "ERR not a shell webapp"; return 1 ;; esac
    file="$APPS/$id.desktop"
    [ -f "$file" ] && grep -q '^X-Shell-Webapp=true' "$file" || { echo "ERR not found"; return 1; }
    fallback="$(sed -n 's/^X-Shell-Webapp-FallbackIcon=//p' "$file" | head -n1)"
    names="$(sed -n 's/^X-Shell-Webapp-ThemeIcons=//p' "$file" | head -n1)"
    # shellcheck disable=SC2086
    icon="$(IFS=';'; themed_icon "${fallback:-applications-internet}" $names)"
    tmp="$(mktemp "$file.XXXXXX")" || { echo "ERR could not write"; return 1; }
    grep -v '^X-Shell-Webapp-CustomIcon=' "$file" > "$tmp" && cat "$tmp" > "$file"
    rm -f "$tmp"
    set_key "$file" Icon "$icon" || { echo "ERR could not write"; return 1; }
    remove_custom_icons "$id"
    refresh_icon_caches
    echo "OK $id"
}

# ── Quick window: a webapp floating over the current workspace (Hyprland special workspace) ──
QUICK_SIZE="(monitor_w*0.55) (monitor_h*0.75)"
DUCK_URL="https://duck.ai/"

# lua_str <text>: quote text as a Lua string for hyprctl dispatch
lua_str() {
    local t="${1//\\/\\\\}"
    t="${t//\'/\\\'}"
    printf "'%s'" "$t"
}

hypr() { hyprctl dispatch "$1" >/dev/null 2>&1; }

# duck_id: the Duck.ai webapp (created on first use)
duck_id() {
    local file
    for file in "$APPS"/$PREFIX*.desktop; do
        [ -e "$file" ] || continue
        grep -q '^X-Shell-Webapp=true' "$file" || continue
        if sed -n 's/^X-Shell-Webapp-Url=//p' "$file" | grep -qE '^https?://(www\.)?duck\.ai(/|$)'; then
            basename "$file" .desktop; return 0
        fi
    done
    create_one "$DUCK_URL" >/dev/null || return 1
    duck_id
}

# quick_target [id]: valid webapp id, or the Duck.ai one
quick_target() {
    local id="${1:-}"
    case "$id" in
        "$PREFIX"?*) [ -f "$APPS/$id.desktop" ] && grep -q '^X-Shell-Webapp=true' "$APPS/$id.desktop" && { echo "$id"; return 0; } ;;
    esac
    duck_id
}

# Window addresses of a webapp (by its window class)
quick_windows() {
    local cls
    cls="$(sed -n 's/^StartupWMClass=//p' "$APPS/$1.desktop" | head -n1)"
    [ -n "$cls" ] || return 0
    hyprctl clients -j 2>/dev/null | jq -r --arg c "$cls" '.[] | select(.class == $c) | "\(.address) \(.workspace.name)"'
}

# quick_launch <id> <special ws> [url]: start the webapp floating, centered, hidden in the special workspace
quick_launch() {
    local id="$1" ws="$2" url="${3:-}" exec_line
    exec_line="$(sed -n 's/^Exec=//p' "$APPS/$id.desktop" | head -n1 | sed -E 's/ %[a-zA-Z]//g')"
    [ -n "$exec_line" ] || return 1
    if [ -n "$url" ]; then
        exec_line="$(EXEC="$exec_line" URL="$url" python3 -I -c 'import os,re; print(re.sub(r"--app=\"[^\"]*\"", lambda m: "--app=\"" + os.environ["URL"] + "\"", os.environ["EXEC"], count=1))')"
    fi
    hypr "hl.dsp.exec_cmd($(lua_str "$exec_line"), { float = true, size = $(lua_str "$QUICK_SIZE"), center = true, workspace = $(lua_str "special:$ws silent") })"
}

# Wait until a window of the webapp that isn't in <old addresses> shows up
quick_wait_new() {
    local id="$1" old="$2" i addr
    for i in $(seq 1 60); do
        addr="$(quick_windows "$id" | cut -d' ' -f1 | grep -vxF -f <(printf '%s\n' "$old") | head -n1)"
        [ -n "$addr" ] && { echo "$addr"; return 0; }
        sleep 0.25
    done
    return 1
}

# quick_adopt <address> <special ws>: move a window into the quick window, floating and centered
quick_adopt() {
    local addr="$1" ws="$2" w h
    read -r w h < <(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | "\((.width / .scale * 0.55) | floor) \((.height / .scale * 0.75) | floor)"')
    hypr "hl.dsp.window.move({ workspace = $(lua_str "special:$ws"), follow = false, window = $(lua_str "address:$addr") })"
    hypr "hl.dsp.window.float({ action = 'enable', window = $(lua_str "address:$addr") })"
    [ -n "$w" ] && hypr "hl.dsp.window.resize({ x = $w, y = $h, exact = true, window = $(lua_str "address:$addr") })"
    hypr "hl.dsp.window.center({ window = $(lua_str "address:$addr") })"
}

shown_special() {
    hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .specialWorkspace.name'
}

# quick_one [id]: show/hide the quick window (opens it the first time)
quick_one() {
    local id ws windows addr wsname
    id="$(quick_target "${1:-}")" || { echo "ERR could not create the Duck.ai webapp"; return 1; }
    ws="webapp-${id#"$PREFIX"}"
    windows="$(quick_windows "$id")"
    if [ -z "$windows" ]; then
        quick_launch "$id" "$ws" || { echo "ERR could not start"; return 1; }
        quick_wait_new "$id" "" >/dev/null || { echo "ERR window did not open"; return 1; }
        hypr "hl.dsp.workspace.toggle_special($(lua_str "$ws"))"
        echo "OK shown"; return 0
    fi
    # Bring windows opened elsewhere (e.g. from the app menu) into the quick window
    while read -r addr wsname; do
        [ "$wsname" = "special:$ws" ] || quick_adopt "$addr" "$ws"
    done <<<"$windows"
    hypr "hl.dsp.workspace.toggle_special($(lua_str "$ws"))"
    echo "OK toggled"
}

# ask_one <text> [id]: ask Duck.ai in the quick window (sent right away; the previous chat stays in its history)
ask_one() {
    local text="$1" id ws old addr q profile i
    text="$(printf '%s' "$text" | tr '\000-\037\177' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ | $//g')"
    [ -n "$text" ] || { echo "ERR empty question"; return 1; }
    id="$(quick_target "${2:-}")" || { echo "ERR could not create the Duck.ai webapp"; return 1; }
    ws="webapp-${id#"$PREFIX"}"
    q="$(printf '%s' "${text:0:2000}" | jq -sRr @uri)"
    old="$(quick_windows "$id" | cut -d' ' -f1)"
    profile="$(sed -n 's/^X-Shell-Webapp-Profile=//p' "$APPS/$id.desktop" | head -n1)"
    # A running browser opens new windows itself, without the launch rules: with its own
    # profile, close the old window first so the new one starts hidden and floating
    if [ -n "$old" ] && [ -n "$profile" ]; then
        for addr in $old; do
            hypr "hl.dsp.window.close({ window = $(lua_str "address:$addr") })"
        done
        old=""
        for i in $(seq 1 40); do
            [ -L "$profile/SingletonLock" ] || break
            sleep 0.1
        done
    fi
    quick_launch "$id" "$ws" "${DUCK_URL}?q=$q&prompt=1" || { echo "ERR could not start"; return 1; }
    addr="$(quick_wait_new "$id" "$old")" || { echo "ERR window did not open"; return 1; }
    # Shared browser profile: the window opened outside the quick window, bring it in
    [ "$(hyprctl clients -j | jq -r --arg a "$addr" '.[] | select(.address == $a) | .workspace.name')" = "special:$ws" ] \
        || quick_adopt "$addr" "$ws"
    for old in $old; do
        hypr "hl.dsp.window.close({ window = $(lua_str "address:$old") })"
    done
    [ "$(shown_special)" = "special:$ws" ] || hypr "hl.dsp.workspace.toggle_special($(lua_str "$ws"))"
    echo "OK $addr"
}

open_one() {
    local id="$1" file exec_line
    case "$id" in "$PREFIX"*) ;; *) echo "ERR not a shell webapp"; return 1 ;; esac
    file="$APPS/$id.desktop"
    [ -f "$file" ] && grep -q '^X-Shell-Webapp=true' "$file" || { echo "ERR not found"; return 1; }
    # Same command as the app launcher (browser + isolated profile chosen at creation)
    exec_line="$(sed -n 's/^Exec=//p' "$file" | head -n1)"
    nohup bash -c "$exec_line" >/dev/null 2>&1 &
}

# Re-pick every webapp's icon for the current icon theme (run when the theme changes).
# Prints CHANGED if any launcher was updated.
retheme_all() {
    local file id icon fallback names new changed=0
    for file in "$APPS"/$PREFIX*.desktop; do
        [ -e "$file" ] || continue
        grep -q '^X-Shell-Webapp=true' "$file" || continue
        grep -q '^X-Shell-Webapp-CustomIcon=' "$file" && continue   # the user's own icon
        id="$(basename "$file" .desktop)"
        icon="$(sed -n 's/^Icon=//p' "$file" | head -n1)"
        fallback="$(sed -n 's/^X-Shell-Webapp-FallbackIcon=//p' "$file" | head -n1)"
        names="$(sed -n 's/^X-Shell-Webapp-ThemeIcons=//p' "$file" | head -n1)"
        if [ -z "$fallback" ]; then
            # Older webapp with an absolute icon path: turn it into a named icon
            if [ -f "$icon" ]; then
                install_fallback_icon "$icon" "$id"; fallback="$id"
            else
                fallback="${icon:-applications-internet}"
            fi
            local url host
            url="$(sed -n 's/^X-Shell-Webapp-Url=//p' "$file" | head -n1)"
            host="$(python3 -I -c 'import sys;from urllib.parse import urlparse;print(urlparse(sys.argv[1]).hostname or "")' "$url")"
            names="$(python3 "$ICON_HELPER" candidates "$host" "$(sed -n 's/^Name=//p' "$file" | head -n1)" 2>/dev/null | paste -sd';')"
            printf 'X-Shell-Webapp-ThemeIcons=%s\nX-Shell-Webapp-FallbackIcon=%s\n' "$names" "$fallback" >> "$file"
        fi
        # shellcheck disable=SC2086
        new="$(IFS=';'; themed_icon "$fallback" $names)"
        if [ "$new" != "$icon" ]; then
            sed -i "s|^Icon=.*|Icon=$new|" "$file"
            changed=1
        fi
    done
    if [ "$changed" = 1 ]; then
        refresh_icon_caches
        echo CHANGED
    fi
}

command="${1:-}"
shift || true
case "$command" in
    create) status=0; for url in "$@"; do create_one "$url" || status=1; done; exit "$status" ;;
    list) list_all ;;
    remove) remove_one "${1:-}" ;;
    open) open_one "${1:-}" ;;
    rename) rename_one "${1:-}" "${2:-}" ;;
    seticon) seticon_one "${1:-}" "${2:-}" ;;
    reseticon) reseticon_one "${1:-}" ;;
    browsers) list_browsers ;;
    retheme) retheme_all ;;
    quick) quick_one "${1:-}" ;;
    ask) ask_one "${1:-}" "${2:-}" ;;
    *) echo "usage: [WEBAPP_BROWSER=cmd] [WEBAPP_ISOLATED=1|0] [WEBAPP_ICON_THEME=name] webapp.sh create <url>... | list | remove <id> | open <id> | rename <id> <name> | seticon <id> <image|icon name> | reseticon <id> | browsers | retheme | quick [id] | ask <question> [id]" >&2; exit 2 ;;
esac
