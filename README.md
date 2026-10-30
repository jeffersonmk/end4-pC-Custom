<div align="center">

# 💠 end4-pC-Custom

**A fork of [end4-pC](https://github.com/pctrade/end4-pC) by [@pctrade](https://github.com/pctrade), itself built on [illogical-impulse](https://github.com/end-4/dots-hyprland) by [@end-4](https://github.com/end-4)**
Customized and maintained by **[@jeffersonmk](https://github.com/jeffersonmk)**

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) *(translations describe the upstream end4-pC)*

</div>

---

## ✨ What's different in this fork

| | |
|---|---|
| ⌨️ **Keybind cheat sheet** | `Super + /` opens a sheet (rounded window or full screen, your choice) with all your Hyprland keybinds grouped into cards (Shell, Window, Workspace, Apps, Media, your own custom binds…) with a live filter. The launcher no longer lists keybinds with `<`. |
| 🖥️ **System tab** | The cheat sheet has a second tab, **System** (`Ctrl + Tab`): CPU, GPU and memory specs, live CPU/GPU usage, temperatures, clocks, VRAM, RAM/swap and per-drive usage for every HDD/SSD/NVMe. AMD, NVIDIA and Intel; no root needed. |
| 🤖 **AI usage tab** | Third cheat sheet tab with the plan limits of **Claude** and **ChatGPT** side by side, each with its logo: usage %, reset countdowns (Claude: 5-hour session + weekly, plus per-model limits when your plan has them; ChatGPT/Codex: the plan's usage windows), extra usage / credits and Claude's weekly usage per product. Reads the local **Claude Code** (`~/.claude/.credentials.json`) and **Codex / ChatGPT desktop** (`~/.codex/auth.json`) logins; **both are off by default** — turn each one on with the button in the tab or in *Settings › Interface › Cheat sheet › AI usage tab*; until then nothing is read or sent. Tokens are only sent to `api.anthropic.com` / `chatgpt.com` and are never refreshed by the shell. Uses the same unofficial endpoints as Claude Code's `/usage` and Codex's `/status`, so it may break if they change. |
| 📊 **AI Usage bar widget** | The bar's *AI Usage* widget shows **Claude Code** and **Codex** side by side, each with its own logo and the plan usage % (Claude: 5-hour session; Codex: the plan window, e.g. monthly on Go). Hover for every limit with progress bars and reset countdown + time (Claude 5-hour and weekly, Codex plan windows, extra usage/credits when on) plus the Claude Code sessions running on the PC. Click the Claude logo to open the **Claude** app, the Codex logo to open the **ChatGPT desktop** app (falls back to the website). Show/hide each one in *Settings › Bar › AI Usage*; the numbers use the same opt-in switches as the AI usage tab (off by default; until on, the widget shows "—"). |
| 🎛️ **Cheat sheet styling** | *Settings › Interface › Cheat sheet*: window or fullscreen mode, Super key symbol (Arch, ⌘, Windows… Nerd Font glyphs), macOS-style modifier symbols, F-key and mouse symbols, split keycaps, font sizes. Same `cheatsheet.*` options as illogical-impulse. |
| 🌙 **Night light menu** | Right-click the night light button in the right sidebar (or *Settings › General › Night light*): set the **on/off times** of the automatic schedule, the color temperature, and what happens **when the PC starts** (off, on, or follow the schedule). Starts **off** by default. |
| 🎵 **Media players overlay** | New widget in the `Super + G` overlay (music note icon in its top bar): every media player open right now with its app icon and name; switch between them, previous / play-pause / next and per-app volume. Works with the controller too. |
| 🎮 **Gamepad support** | *Settings › Services › Gamepad*: press a controller button (default: the Xbox / PS / Nintendo *home* button) to open the widget overlay, the same as `Super + G`, or any other panel you pick. While the overlay is open you can **drive it with the controller**: d-pad / left stick moves a focus ring between every button, tab (e.g. Output/Input, CPU/RAM/Swap) and slider, the bottom button (A / ✕ / B) selects, left/right changes a focused slider (e.g. an app's volume), the right button (B / ○ / A) or Start closes it and the bumpers change the system volume. While it's open the controller works **only in the overlay** (buttons, sticks, touchpad and motion sensors are taken from the game/app behind it until you close it), and the focused game can be **paused** until you close it: separate switches for Xbox/standard controllers and for PlayStation/Nintendo ones (on by default, since emulators and Steam read those directly). A hint bar shows your controller's **brand logo** (Xbox, PlayStation or Nintendo) and its button labels. Works with USB and Bluetooth controllers plugged in at any time; outside the overlay games receive every button as usual. Off by default; needs `python-evdev` (`sudo pacman -S python-evdev`). |
| 🔍 **Search inside Settings** | A **Search** button in the Settings sidebar (or `Ctrl + F`) finds any page, section or option by keyword and jumps straight to it. |
| 📐 **Roomier Settings panel** | Bigger, better-proportioned window; nothing is cut off at the bottom of the sidebar. |
| 🔐 **Login screen (SDDM)** | *Settings › Login screen*: restyle the [sddm-theme-corners](https://github.com/aczw/sddm-theme-corners) login screen from the shell. Pick the **current wallpaper** or any other image as the background, **generate the colors from your wallpaper palette** (login button, fields, popups, session/power buttons, date and time), choose the **font**, the **date / clock size and weight** (defaults taken from the dotfiles: Atkinson Hyperlegible, date 36 regular, clock 48 bold, 12-hour), **override the color of any element** (date, clock, text boxes, login / session / power buttons, menus…) with a hex value, and pick the features: user photo, show password, 24-hour clock, corner radius, login button text. Nothing changes until you press **Apply to SDDM**. Needs a one-time setup, see [Login screen (SDDM)](#-login-screen-sddm-optional). |
| 🧹 **Features removed** | The left-sidebar *Translator* tab, the *Screen Translator* (`Super + Shift + T`), **Google Lens** (image search button), **music recognition** (SongRec button), the Gemini clock auto-styling and the Gemini *translation generator* (welcome screen and *Settings › General › Language*) were removed. The **Dashboard** style of the Settings panel and the **Football** sidebar page (sports betting parlays) are not included either. `Super + Shift + T` can open the System tab instead (see below). |
| 🖥️ **Local-only AI chat** | The *Intelligence* sidebar only talks to models running on your machine (Ollama, vLLM, or any OpenAI-compatible server on `localhost`). Online models, API keys and the `/key` command were removed. |
| 🎨 **Clock presets** | *Settings › Desktop › Cookie clock settings › Clock preset*: choose a visual style for the cookie clock — None (manual), Abstract, Anime, City/Space, Minimalist, Landscape, Plants, Person. No AI or API key needed. |
| 🍅 **Digital Pomodoro** | The Pomodoro in the right sidebar (*Timer* tab) has a **digital clock** view next to the dial: phase, cycle, big countdown and progress bar, with **−/+** buttons to change the **focus** and **break** length right there (locked while it's running). Switch with the button at the top right, or in *Settings › General › Time › Pomodoro*, which also has the long break length and cycles. |
| 🖼️ **HD album covers** | Covers are upgraded to high resolution (up to 1000–1200 px): first by asking the player itself for a bigger image (YouTube/YouTube Music, Google, Jellyfin, Navidrome), then by looking the album up on **iTunes**, **Deezer** and **MusicBrainz / Cover Art Archive**. On YouTube the real album cover is preferred over the video thumbnail (also for "Artist - Topic" / VEVO channels); a music-note icon is shown instead of a blurry crop. Downloads never show a half-loaded image. *Clear cover cache* in the player's ⋮ menu. |
| 🎤 **Better synced lyrics** | Smarter LRCLIB lookups (several artist/title/album combinations, duration matching), so tracks with multiple artists find their lyrics. Lyrics without timestamps still scroll along with the song, with a **Not synced** badge; when there are none you get *Lyrics not available* and a **Try again** button. Seeking resyncs the lyrics. |
| 🎚️ **Player selector** | The left-sidebar player has a working app selector with friendly names (no duplicates, no `playerctld`). It **follows whatever starts playing**, but an app you picked by hand stays selected while it's playing; when it closes it goes back to automatic. |
| 🌐 **Webapps, isolated** | *Settings › Services › Webapps*: choose the **browser** (Automatic, Brave, Helium, Chromium, Chrome, Vivaldi, Edge, Thorium — whatever is installed) and give every webapp its **own isolated profile** (separate logins, cookies and cache, own window), like Linux Mint's *webapp-manager*. Removing a webapp also deletes its profile. Webapp icons **follow your icon theme** (e.g. Papirus' WhatsApp/YouTube Music icons) and fall back to the site's own icon. Rename a webapp or **click its icon to pick your own** (a theme icon or any image); the workspace indicator shows the webapp's icon too. |
| 🦆 **Duck.ai quick window** | `Super + Shift + D` shows/hides **Duck.ai** floating and centered over any workspace (the conversation stays there while hidden). In the app menu, type **`duck` + your question** and press Enter to ask it right away. It uses your Duck.ai webapp (created on first use, or again if you delete it, with your icon theme's DuckDuckGo icon); *Settings › Services › Webapps › Quick window* can put another webapp on the shortcut. Hyprland binding: `hl.bind("SUPER + SHIFT + D", hl.dsp.global("quickshell:webappQuickToggle"))`. |
| ☁️ **MEGA cloud next to your drives** | The cheat sheet's **System** tab (`Super + /`) shows a **MEGA** card in *Storage*, beside your drives: used / total space, whether it's synced, syncing (with %) or has a problem, your synced folders and transfers, plus a button to open MEGA (your MEGA webapp if you have one). There's also a **MEGA bar widget** (*Settings › Bar*): a simple sync-state icon; hover it to see how much MEGA space is used and free, synced folders and transfers, click to open MEGA, right click to refresh. Needs [MEGAcmd](https://github.com/meganz/MEGAcmd) (`paru -S megacmd`) and a one-time `mega-login you@email` in a terminal — the shell only reads the status and never sees your password. |
| 📁 **Papirus folder color** | *Settings › Quick › Papirus folder color* shows every Papirus folder color (all 25, drawn with the real icons) plus **Auto** and **Default**. **Auto** picks, after every wallpaper or color change, the Papirus color closest to your wallpaper; a **fixed color** stays when the wallpaper changes; **Default** is plain Papirus. It builds a tiny theme (`Papirus-Dark-Folder-<color>`, about 3 MB, hidden from the icon-theme list) in `~/.local/share/icons` that inherits Papirus and only repoints the folder icons, so the system theme is never touched. Works with Papirus, Papirus-Dark and Papirus-Light; any other icon theme is left alone. |
| 🎞️ **Wallpaper Engine Workshop** | In the wallpaper selector pick **Steam Workshop**. **Online** (☁️) browses the public Workshop (trending, most recent, most subscribed, search, *Anime only*, and a type button: *Video*, *Scene* or both) with no login and no API key; click a wallpaper to open it in Steam and press *Subscribe*. **My library** (🎞️) lists everything Steam says you are subscribed to: **Downloaded**, **Not downloaded** (subscribed but the files are missing) and **Unsupported** (Web/Application, and Scene when `linux-wallpaperengine` is missing; shown dimmed), with the size on disk. A second row, **Source**, separates what came from the **Steam Workshop** from what did not: wallpapers *made in* or *built into* Wallpaper Engine, and the plain video files in your *Live Wallpaper Folder* (Settings › Interface). Only Workshop downloads can be deleted; click a downloaded Video or Scene to set it. **Download all** (and the ☁️ button on a card) asks your running Steam client to download every subscribed wallpaper missing from the PC, with a progress bar and *Cancel*, without opening any window. It also brings back wallpapers you deleted here, which Steam alone never downloads again. It is off until you confirm it once (or turn on Settings › Interface › *Steam Workshop: download through Steam*): it uses Valve's Steamworks library (`libsteam_api.so`), fetched once from the Steamworks.NET project at a fixed version, checked against a fixed SHA-256 before every use and kept in `~/.local/share/quickshell/steamworks` (not in this repo). No password is used; while it downloads Steam shows you as playing Wallpaper Engine. Hover a card to **delete** its downloaded files (or use **Delete downloaded** for the whole list); deleting never unsubscribes you, the card has a button to open its Workshop page for that. A **18+** button shows or hides *Questionable* and *Mature* items (hidden by default, in both views). The ✅ **Requirements** button lists what is needed and what is missing: Steam (open and signed in for downloads), Wallpaper Engine installed in Steam (Scene wallpapers use its files), `mpvpaper`, `linux-wallpaperengine`, the Steam download helper (installed on the first *Download all*), `ffmpeg`, `xdg-open` and internet. *Video* wallpapers play with `mpvpaper`; *Scene* wallpapers play with [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) (`paru -S linux-wallpaperengine-git`; it uses the assets of your Wallpaper Engine install). It is unofficial: most scenes work, a few render with missing effects, and 3D scenes do not run yet (they are marked *Scene: won't run* and your previous wallpaper is kept). The theme colours come from a frame of the running scene, it pauses by itself when a game is fullscreen, and Settings › Background › Live wallpaper sets its FPS limit (default 30) and sound (off by default). *Web* and *Application* wallpapers cannot be applied. |
| 🔔 **Clear notification buttons** | Every button on a notification balloon has an icon **and** a label (✕ Close, ↗ Open, ⧉ Copy). Apps that send their click action with no label no longer get a blank button: it becomes **Open**. Copy shows **Copied!** for a moment. |
| ☕ **Keep system awake, reliably** | The *Keep system awake* toggle keeps working when a monitor disconnects/reconnects (before, the PC could still suspend while the toggle looked on). |
| 📁 **Install-folder independent** | Lock screen (Niri) and *About › Update Dots* work whatever the folder is called, so this fork can live next to `end4-pC` and `ii`. |

Everything else (bar, widgets, wallpapers, Hyprland settings, presets…) comes from end4-pC and is kept in sync with it.

---

## 📸 Screenshots

### What this fork adds

<div align="center">

| ⌨️ Keybind cheat sheet (`Super + /`) |
|:---:|
| ![Keybind cheat sheet](screenshots/fork/cheatsheet-keybinds.webp) |
| 🖥️ **System tab** — specs, usage, temperatures and drives |
| ![System tab](screenshots/fork/cheatsheet-system.webp) |

| 🎵 HD cover, synced lyrics, player selector | 🌙 Night light menu |
|:---:|:---:|
| ![Left sidebar player](screenshots/fork/sidebar-player.webp) | ![Night light menu](screenshots/fork/night-light-menu.webp) |

| 🎵 Media players overlay | 🍅 Digital Pomodoro |
|:---:|:---:|
| ![Media players widget](screenshots/fork/overlay-media-players.webp) | ![Digital Pomodoro](screenshots/fork/pomodoro-digital.webp) |

| 🎮 Gamepad hint bar in the overlay (controller brand + button labels) |
|:---:|
| ![Gamepad hint bar](screenshots/fork/overlay-gamepad-hints.webp) |

| 🔍 Search inside Settings | 🌐 Webapps: browser choice + isolated profiles |
|:---:|:---:|
| ![Settings search](screenshots/fork/settings-search.webp) | ![Webapps settings](screenshots/fork/settings-webapps.webp) |

</div>

### From end4-pC
<div align="center">

| 🎵 Lyrics | 🖼️ Online Wallpapers |
|:---:|:---:|
| ![Screenshot 1](screenshots/1.png) | ![Screenshot 2](screenshots/2.png) |
| 🪟 Desktop Widgets | 🔧 Hyprland Configs |
| ![Screenshot 5](screenshots/5.png) | ![Screenshot 6](screenshots/6.png) |
| ⚙️ Configurable Bar | ✨ And More |
| ![Screenshot 3](screenshots/3.png) | ![Screenshot 4](screenshots/4.png) |

<sub>Screenshots from upstream end4-pC.</sub>

</div>

---

## 🎨 Presets

Save your whole desktop look as a preset in **Settings → your profile (top of the sidebar) → Presets**, export it as a ZIP or import one. You can also browse the **[end4-pCpresets](https://github.com/pctrade/end4-pCpresets)** community gallery and press **Download** to try a preset or **Install** to keep it. Uploading presets to the gallery was removed from this fork.

---

## ⚡ Installation

> [!NOTE]
> This fork lives in its own folder (`~/.config/quickshell/end4-pC-Custom`) and does **not** touch `ii` or `end4-pC`. It requires [illogical-impulse](https://github.com/end-4/dots-hyprland) to be installed, since it uses its Hyprland config, scripts and keyring entry.

```bash
cd ~/.config/quickshell/
git clone https://github.com/jeffersonmk/end4-pC-Custom.git
killall qs 2>/dev/null; qs -c end4-pC-Custom > /dev/null 2>&1 & disown
```

### 🔧 Set as your default shell

The illogical-impulse keybinds (launcher on `Super`, clipboard, emoji, etc.) talk to the shell named in `qsConfig`. If it doesn't match the running shell, they fall back to fuzzel. To use this fork for real, edit:

```bash
~/.config/hypr/hyprland/variables.lua
```

and set:

```lua
hl.env("qsConfig", "end4-pC-Custom")
```

> [!TIP]
> After saving, restart Hyprland or run `hyprctl reload`. To go back, put the previous value (`ii` or `end4-pC`) back.

### ⚙️ Settings keybind

To open the settings panel, add this to your Hyprland config:

```lua
hl.bind("SUPER + escape", hl.dsp.global("quickshell:settingsToggle"), {description = "Toggle settings"})
```

> **Note:** Settings is an overlay panel, not a regular window, so `Super + Q` won't close it. Use the same keybind or press `Escape`.

### 🖥️ System info keybind (optional)

To open the cheat sheet straight on the **System** tab (hardware, usage, temperatures), add this to `~/.config/hypr/custom/keybinds.lua`:

```lua
hl.unbind("SUPER + SHIFT + T") -- free the old screen translator bind
hl.bind("SUPER + SHIFT + T", hl.dsp.global("quickshell:systemInfoToggle"), {description = "Utilities: System info and temperatures"})
```

### 🔐 Login screen (SDDM) (optional)

Requires SDDM with the `corners` theme installed (`paru -S sddm-theme-corners-git`) and selected (`Current=corners` in `/etc/sddm.conf` or `/etc/sddm.conf.d/`).

**Install** (once; asks for your password):

```bash
bash ~/.config/quickshell/end4-pC-Custom/scripts/sddm/install.sh
```

This copies a small helper to `/usr/local/bin/sddm-corners-apply` (owned by root) and adds a sudoers rule that lets your user run **only that file** without a password. The helper accepts only known theme keys, `#rrggbb` colors and a PNG/JPG/WEBP image from your home folder; it copies the image into the theme's `backgrounds/` folder and rewrites `theme.conf` (the original is saved once as `theme.conf.orig`).

**Use:** open *Settings › Login screen*, choose the image and options, press **Apply to SDDM**. Log out to see the result (the lock screen is not affected). Live/video wallpapers cannot be used; pick a still image.

**Update:** *Update Dots* / `git pull` updates the page and scripts. If `scripts/sddm/sddm-corners-apply` changed (it did when fonts, sizes and per-element colors were added), run `install.sh` again, otherwise *Apply* is rejected by the old helper.

**Uninstall:**

```bash
bash ~/.config/quickshell/end4-pC-Custom/scripts/sddm/uninstall.sh
```

This removes the helper and the sudoers rule. To also restore the original look: `sudo cp /usr/share/sddm/themes/corners/theme.conf.orig /usr/share/sddm/themes/corners/theme.conf`.

### 🔄 Updating

*Settings › About › Update Dots* re-downloads this repository into the folder the shell is running from and restarts it. Or manually:

```bash
cd ~/.config/quickshell/end4-pC-Custom && git pull
```

---

## ❓ FAQ

### How do I see my keybinds?

Press `Super + /`. Type in the filter at the bottom to narrow them down (by description, category or key). `Esc` clears the filter, then closes.

### How do I find a setting?

Open Settings and click **Search** in the sidebar (or press `Ctrl + F`), type a keyword (`blur`, `wallpaper`, `font`…) and press `Enter`. You can also type the keyword in the launcher (`Super`).

### How do I use the AI chat?

Install [Ollama](https://ollama.com), pull a model (e.g. `ollama pull llama3.2`), open the left sidebar and type `/refresh`. Choose a model with `/model`. Other local OpenAI-compatible servers can be added in `ai.extraModels` in `~/.config/illogical-impulse/config.json` (endpoints that aren't on `localhost` are ignored).

### Why is my SATA SSD/HDD temperature missing in the System tab?

NVMe drives report their temperature out of the box. SATA drives need the `drivetemp` kernel module: run `sudo modprobe drivetemp`, and to load it on every boot, `echo drivetemp | sudo tee /etc/modules-load.d/drivetemp.conf`.

---

## 🙏 Credits

- **[@end-4](https://github.com/end-4)**: creator of [dots-hyprland](https://github.com/end-4/dots-hyprland) / illogical-impulse 🫡
- **[@pctrade](https://github.com/pctrade)**: creator and maintainer of [end4-pC](https://github.com/pctrade/end4-pC), which this fork is based on
- **[@gh0stzk](https://github.com/gh0stzk)**: weather API integration
- **[@StarS2112](https://github.com/StarS2112)**: showcasing end4-pC
- **[@simeulinuxkaliaiwr](https://github.com/simeulinuxkaliaiwr)**: shader transitions

---

<div align="center">

Licensed under the [GPL-3.0](LICENSE), like the projects it's based on.

</div>
