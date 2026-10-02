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
        if (isButton(item) || isSlider(item)) {
            if (reallyVisible(item)) out.push(item);
            if (isSlider(item)) return; // don't descend into slider handles
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

    // ---- movement
    function pickInitial(list) {
        // Prefer the first open widget's toggle in the taskbar, else the first target
        const toggled = list.find(t => t.toggled === true);
        return toggled ?? list[0] ?? null;
    }
    function move(direction) {
        const list = targets();
        if (list.length === 0) { root.current = null; return; }
        if (!root.current || !list.includes(root.current)) {
            root.current = pickInitial(list);
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
        const horizontal = direction === "left" || direction === "right";
        // First look only at targets in the same row (or column); if there are none,
        // fall back to anything in that direction. Avoids e.g. "right" on the last
        // tab jumping up to a title bar button.
        const pick = aligned => {
            let best = null;
            let bestScore = Infinity;
            for (const t of list) {
                if (t === root.current) continue;
                const c = centerOf(t);
                const dx = c.x - from.x;
                const dy = c.y - from.y;
                let primary, secondary;
                switch (direction) {
                    case "right": primary = dx; secondary = dy; break;
                    case "left": primary = -dx; secondary = dy; break;
                    case "down": primary = dy; secondary = dx; break;
                    default: primary = -dy; secondary = dx; break;
                }
                if (primary <= 4) continue;
                if (aligned) {
                    const reach = horizontal ? (root.current.height + t.height) / 2 : (root.current.width + t.width) / 2;
                    if (Math.abs(secondary) > reach) continue;
                }
                const score = primary + 2.5 * Math.abs(secondary);
                if (score < bestScore) { bestScore = score; best = t; }
            }
            return best;
        };
        const best = pick(true) ?? pick(false);
        if (best) root.current = best;
    }
    function activate() {
        const t = root.current;
        if (!t || !targets().includes(t)) { move("down"); return; }
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
                case "BTN_START": GlobalStates.overlayOpen = false; break;
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
        else root.current = null;
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
            Hint { glyph: "✥"; label: Translation.tr("Move") }
            Hint { glyph: Gamepad.buttonGlyph("BTN_SOUTH"); label: Translation.tr("Select") }
            Hint { glyph: Gamepad.buttonGlyph("BTN_EAST"); label: Translation.tr("Close") }
            Hint {
                glyph: `${Gamepad.buttonGlyph("BTN_TL")} ${Gamepad.buttonGlyph("BTN_TR")}`
                label: root.toast.length > 0 ? root.toast : Translation.tr("Volume")
            }
        }
    }

    component Hint: Row {
        id: hint
        property string glyph
        property string label
        spacing: 6
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.max(26, glyphText.implicitWidth + 12)
            implicitHeight: 26
            radius: height / 2
            color: Appearance.colors.colSecondaryContainer
            StyledText {
                id: glyphText
                anchors.centerIn: parent
                text: hint.glyph
                color: Appearance.colors.colOnSecondaryContainer
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.label
            color: Appearance.colors.colOnSurface
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}
