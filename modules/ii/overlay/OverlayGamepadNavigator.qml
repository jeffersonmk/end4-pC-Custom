pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Lets a game controller drive the widget overlay (Super + G):
 *  - d-pad / left stick: move a focus ring between every button and slider on screen
 *    (taskbar widget toggles, recorder buttons, widget title bar buttons, volume sliders…)
 *  - bottom face button (A / ✕): press the focused button
 *  - left/right on a focused slider: change its value (e.g. an app's volume)
 *  - on a dropdown (e.g. the output/input device): left/right switches option directly;
 *    A / ✕ opens the list, up/down picks, A / ✕ confirms, B / ○ cancels
 *  - right face button (B / ○) or Start: close the overlay
 *  - bumpers (LB/RB, L1/R1): system volume down/up
 * Also shows a hint bar with the controller brand logo and the button legend.
 *
 * Targets are found by walking the overlay's item tree, so widgets don't need
 * any changes to be reachable.
 */
Item {
    id: root

    required property Item scope            // overlay content to search for targets
    property Item current: null              // focused target
    property string toast: ""                // short feedback (volume level)

    readonly property bool active: Gamepad.navActive

    // ---- target discovery
    function isButton(item) {
        // Any Qt Quick button: RippleButton, tab buttons (Output/Input, CPU/RAM/Swap…), switches
        return typeof item.click === "function" && item.checkable !== undefined && item.pressed !== undefined;
    }
    function isComboBox(item) {
        return typeof item.incrementCurrentIndex === "function" && item.popup !== undefined && item.count !== undefined;
    }
    function isSlider(item) {
        return typeof item.increase === "function" && item.stepSize !== undefined && item.orientation !== undefined;
    }
    function reallyVisible(item) {
        if (!item.visible || !item.enabled || item.opacity <= 0.01 || item.width < 4 || item.height < 4) return false;
        const c = item.mapToItem(root, item.width / 2, item.height / 2);
        if (c.x < 0 || c.y < 0 || c.x > root.width || c.y > root.height) return false;
        // Hidden by a clipping ancestor (e.g. the other page of a SwipeView)?
        for (let p = item.parent; p && p !== root.scope; p = p.parent) {
            if (p.clip) {
                const q = item.mapToItem(p, item.width / 2, item.height / 2);
                if (q.x < 0 || q.y < 0 || q.x > p.width || q.y > p.height) return false;
            }
            if (p.opacity <= 0.01) return false;
        }
        return true;
    }
    function collect(item, out) {
        if (!item || item === root) return;
        if (!item.visible) return;
        if (isButton(item) || isSlider(item) || isComboBox(item)) {
            if (reallyVisible(item)) out.push(item);
            if (isSlider(item) || isComboBox(item)) return; // don't descend into their internals
        }
        const kids = item.children;
        for (let i = 0; i < kids.length; i++) collect(kids[i], out);
    }
    function targets() {
        const out = [];
        collect(root.scope, out);
        return out;
    }
    function centerOf(item) {
        return item.mapToItem(root, item.width / 2, item.height / 2);
    }
    // Overlay widget (StyledOverlayWidget) an item belongs to
    function widgetOf(item) {
        for (let p = item; p; p = p.parent) {
            if (p.overlayWidget !== undefined) return p.overlayWidget;
            if (p.persistentStateEntry !== undefined && p.identifier !== undefined) return p;
        }
        return null;
    }
    function rectOf(item) {
        const p = item.mapToItem(root, 0, 0);
        return { x1: p.x, y1: p.y, x2: p.x + item.width, y2: p.y + item.height };
    }
    // Distance between two ranges (0 when they overlap)
    function rangeGap(a1, a2, b1, b2) {
        return Math.max(0, Math.max(a1, b1) - Math.min(a2, b2));
    }

    // ---- movement
    function pickInitial(list) {
        // Prefer the first open widget's toggle in the taskbar, else the first target
        const toggled = list.find(t => t.toggled === true);
        return toggled ?? list[0] ?? null;
    }
    // Dropdown whose list is open (navigation goes to the list instead of the screen)
    readonly property bool comboOpen: current !== null && isComboBox(current) && (current.popup?.visible ?? false)

    Connections {
        target: (root.current !== null && root.isComboBox(root.current)) ? root.current.popup : null
        function onVisibleChanged() {
            if (root.current && !root.current.popup.visible && "showHighlight" in root.current) root.current.showHighlight = false;
        }
    }

    function comboChoose(combo, index) {
        if (index < 0 || index >= combo.count) return;
        // Emitting activated() runs the widget's own handler (e.g. set default sink),
        // without breaking its currentIndex binding
        if (index !== combo.currentIndex) combo.activated(index);
        root.showToast(combo.textAt(index));
    }

    function move(direction) {
        if (root.comboOpen) {
            const c = root.current;
            if ("setNavIndex" in c) {
                if (direction === "down") c.setNavIndex(c.navIndex + 1);
                else if (direction === "up") c.setNavIndex(c.navIndex - 1);
            } else {
                if (direction === "down") c.incrementCurrentIndex();
                else if (direction === "up") c.decrementCurrentIndex();
            }
            return;
        }
        const list = targets();
        if (list.length === 0) { root.current = null; return; }
        if (!root.current || !list.includes(root.current)) {
            root.current = pickInitial(list);
            return;
        }
        if (isComboBox(root.current) && (direction === "left" || direction === "right")) {
            const c = root.current;
            if (c.count > 1) root.comboChoose(c, (c.currentIndex + (direction === "right" ? 1 : -1) + c.count) % c.count);
            return;
        }
        if (isSlider(root.current) && (direction === "left" || direction === "right")) {
            const s = root.current;
            const before = s.value;
            if (direction === "right") s.increase(); else s.decrease();
            if (s.value === before) {
                // stepSize 0: nudge by 5% of the range
                const step = (s.to - s.from) * 0.05;
                s.value = Math.max(s.from, Math.min(s.to, s.value + (direction === "right" ? step : -step)));
            }
            s.moved();
            root.showToast(`${Math.round(100 * (s.value - s.from) / ((s.to - s.from) || 1))}%`);
            return;
        }
        const from = centerOf(root.current);
        const fr = rectOf(root.current);
        const horizontal = direction === "left" || direction === "right";
        // Distances are measured between the edges of the items, not their centers:
        // a wide slider right below a button must not win over the tabs that sit
        // between them (e.g. Recorder › "Open recordings folder" › Output/Input tabs).
        // First look only at targets in the same row (or column); if there are none,
        // fall back to anything in that direction. Avoids e.g. "right" on the last
        // tab jumping up to a title bar button.
        // Moving up/down, a widget's title bar buttons (pin/close) are only reachable from
        // inside that same widget: going down from the Recorder lands on the Volume
        // Mixer tabs, not on its close button
        const currentWidget = widgetOf(root.current);
        const skipTitlebar = t => !horizontal && t.overlayTitlebarButton === true
            && t.overlayWidget !== currentWidget;
        const pick = aligned => {
            let best = null;
            let bestScore = Infinity;
            for (const t of list) {
                if (t === root.current || skipTitlebar(t)) continue;
                const c = centerOf(t);
                const r = rectOf(t);
                const dx = c.x - from.x;
                const dy = c.y - from.y;
                let ahead, gap, sideGap, sideCenter;
                switch (direction) {
                    case "right": ahead = dx; gap = r.x1 - fr.x2; sideGap = rangeGap(fr.y1, fr.y2, r.y1, r.y2); sideCenter = dy; break;
                    case "left": ahead = -dx; gap = fr.x1 - r.x2; sideGap = rangeGap(fr.y1, fr.y2, r.y1, r.y2); sideCenter = dy; break;
                    case "down": ahead = dy; gap = r.y1 - fr.y2; sideGap = rangeGap(fr.x1, fr.x2, r.x1, r.x2); sideCenter = dx; break;
                    default: ahead = -dy; gap = fr.y1 - r.y2; sideGap = rangeGap(fr.x1, fr.x2, r.x1, r.x2); sideCenter = dx; break;
                }
                if (ahead <= 4) continue;
                if (aligned && sideGap > 0) continue;
                const score = Math.max(0, gap) + 2.5 * sideGap + 0.2 * Math.abs(sideCenter);
                if (score < bestScore) { bestScore = score; best = t; }
            }
            return best;
        };
        const best = pick(true) ?? pick(false);
        if (best) root.current = best;
    }
    function activate() {
        const t = root.current;
        if (root.comboOpen) {
            const index = ("navIndex" in t && t.navIndex >= 0) ? t.navIndex : t.highlightedIndex;
            t.popup.close();
            root.comboChoose(t, index);
            return;
        }
        if (!t || !targets().includes(t)) { move("down"); return; }
        if (isComboBox(t)) {
            t.popup.open();
            if ("showHighlight" in t) {
                t.showHighlight = true;
                t.setNavIndex(t.currentIndex);
            }
            return;
        }
        if (isButton(t)) {
            if (t.downAction) t.downAction();
            if (t.releaseAction) t.releaseAction();
            t.click();
        }
    }
    function showToast(text) {
        root.toast = text;
        toastTimer.restart();
    }

    Connections {
        target: Gamepad
        function onNavigated(direction) {
            root.move(direction);
        }
        function onButtonPressed(button) {
            switch (button) {
                case "BTN_SOUTH": root.activate(); break;
                case "BTN_EAST":
                case "BTN_START":
                    if (root.comboOpen) root.current.popup.close();
                    else GlobalStates.overlayOpen = false;
                    break;
                case "BTN_TL":
                    Audio.decrementVolume();
                    root.showToast(Translation.tr("Volume %1%").arg(Math.round(Audio.value * 100)));
                    break;
                case "BTN_TR":
                    Audio.incrementVolume();
                    root.showToast(Translation.tr("Volume %1%").arg(Math.round(Audio.value * 100)));
                    break;
            }
        }
    }
    onActiveChanged: {
        if (active) Qt.callLater(() => root.current = root.pickInitial(root.targets()));
        else {
            if (root.comboOpen) root.current.popup.close();
            root.current = null;
        }
    }
    Timer {
        id: toastTimer
        interval: 1500
        onTriggered: root.toast = ""
    }
    // Widgets can be dragged or opened/closed: keep the ring glued to its target
    // (also picks the first target once the overlay has finished fading in)
    Timer {
        running: root.active
        interval: 120
        repeat: true
        onTriggered: {
            if (root.current && !root.reallyVisible(root.current)) root.current = null;
            if (!root.current) root.current = root.pickInitial(root.targets());
            focusRing.sync();
        }
    }

    // ---- focus ring
    Rectangle {
        id: focusRing
        visible: root.active && root.current !== null
        color: "transparent"
        border.width: 3
        border.color: Appearance.colors.colPrimary
        radius: (root.current?.buttonRadius ?? 12) + 4
        z: 1000

        function sync() {
            if (!root.current) return;
            const p = root.current.mapToItem(root, 0, 0);
            x = p.x - 4;
            y = p.y - 4;
            width = root.current.width + 8;
            height = root.current.height + 8;
        }
        Connections {
            target: root
            function onCurrentChanged() { focusRing.sync(); }
        }
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    // ---- hint bar with the controller brand
    Rectangle {
        id: hintBar
        visible: root.active
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 40
        }
        z: 1000
        implicitWidth: hintRow.implicitWidth + 28
        implicitHeight: 48
        radius: height / 2
        color: Appearance.m3colors.m3surfaceContainer
        border.color: Appearance.colors.colOutlineVariant
        border.width: 1

        RowLayout {
            id: hintRow
            anchors.centerIn: parent
            spacing: 14

            StyledText {
                text: Gamepad.brandGlyph
                font.family: Appearance.font.family.iconNerd
                font.pixelSize: 26
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: Gamepad.brandNames[Gamepad.brand] ?? ""
                color: Appearance.colors.colOnSurface
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            Rectangle {
                implicitWidth: 1
                implicitHeight: 22
                color: Appearance.colors.colOutlineVariant
            }
            Hint {
                label: Translation.tr("Move")
                SymbolBadge { symbol: "gamepad" }
            }
            Hint {
                label: root.comboOpen ? Translation.tr("Choose") : Translation.tr("Select")
                FaceBadge { button: "BTN_SOUTH" }
            }
            Hint {
                label: root.comboOpen ? Translation.tr("Cancel") : Translation.tr("Close")
                FaceBadge { button: "BTN_EAST" }
            }
            Hint {
                visible: Gamepad.pausedGame.length > 0
                label: Translation.tr("Game paused")
                SymbolBadge { symbol: "pause"; filled: true }
            }
            Hint {
                label: root.toast.length > 0 ? root.toast : Translation.tr("Volume")
                BumperBadge { button: "BTN_TL" }
                BumperBadge { button: "BTN_TR" }
            }
        }
    }

    // One legend entry: badge(s) + label
    component Hint: RowLayout {
        id: hint
        property string label
        default property alias badges: badgeRow.data
        spacing: 7
        Row {
            id: badgeRow
            Layout.alignment: Qt.AlignVCenter
            spacing: 4
        }
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: hint.label
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    readonly property int badgeSize: 26

    // Round badge with a Material Symbol (d-pad, pause...)
    component SymbolBadge: Rectangle {
        id: symbolBadge
        property string symbol
        property bool filled: false
        implicitWidth: root.badgeSize
        implicitHeight: root.badgeSize
        radius: width / 2
        color: Appearance.colors.colSecondaryContainer
        MaterialSymbol {
            anchors.centerIn: parent
            text: symbolBadge.symbol
            iconSize: 18
            fill: symbolBadge.filled ? 1 : 0
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    // Face button the way it looks on the controller: PlayStation shapes in their
    // colors, Xbox / Nintendo letters
    readonly property var psShapes: ({
        "BTN_SOUTH": { symbol: "close", color: "#7fb2ea" },
        "BTN_EAST": { symbol: "circle", color: "#ff7a7a" },
        "BTN_NORTH": { symbol: "change_history", color: "#4fd1b4" },
        "BTN_WEST": { symbol: "crop_square", color: "#e88cd2" },
    })
    readonly property var xboxColors: ({
        "BTN_SOUTH": "#7ccf5a", "BTN_EAST": "#f0605a", "BTN_NORTH": "#f2c94c", "BTN_WEST": "#5aa9f0",
    })
    component FaceBadge: Rectangle {
        id: faceBadge
        property string button
        readonly property var ps: Gamepad.brand === "playstation" ? (root.psShapes[button] ?? null) : null
        implicitWidth: root.badgeSize
        implicitHeight: root.badgeSize
        radius: width / 2
        color: Appearance.colors.colSecondaryContainer
        MaterialSymbol {
            visible: faceBadge.ps !== null
            anchors.centerIn: parent
            text: faceBadge.ps?.symbol ?? ""
            iconSize: faceBadge.button === "BTN_EAST" ? 15 : 17
            fill: 0
            font.weight: Font.Bold
            color: faceBadge.ps?.color ?? Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            visible: faceBadge.ps === null
            anchors.centerIn: parent
            text: Gamepad.buttonGlyph(faceBadge.button)
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.Bold
            color: Gamepad.brand === "xbox" ? (root.xboxColors[faceBadge.button] ?? Appearance.colors.colOnSecondaryContainer)
                : Appearance.colors.colOnSecondaryContainer
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Shoulder button: a pill rounded more on the outer top corner, like the real bumper
    component BumperBadge: Rectangle {
        id: bumperBadge
        property string button
        readonly property bool isLeft: button === "BTN_TL" || button === "BTN_TL2"
        implicitWidth: Math.max(34, bumperText.implicitWidth + 14)
        implicitHeight: root.badgeSize - 4
        anchors.verticalCenter: parent?.verticalCenter
        topLeftRadius: isLeft ? height * 0.75 : height * 0.3
        topRightRadius: isLeft ? height * 0.3 : height * 0.75
        bottomLeftRadius: height * 0.3
        bottomRightRadius: height * 0.3
        color: Appearance.colors.colSecondaryContainer
        StyledText {
            id: bumperText
            anchors.centerIn: parent
            text: Gamepad.buttonGlyph(bumperBadge.button)
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnSecondaryContainer
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
