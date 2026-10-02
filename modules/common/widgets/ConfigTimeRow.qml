import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * Label + hour and minute fields for a "HH:mm" (24 h) value.
 * Emits edited("HH:mm") when the user changes it.
 */
RowLayout {
    id: root
    property string text: ""
    property string icon: ""
    property string value: "00:00"
    property int minuteStep: 5
    property real fieldHeight: 35
    signal edited(string newValue)

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    property bool syncing: false
    function sync() {
        const parts = String(root.value).split(":");
        root.syncing = true;
        hoursBox.value = Math.max(0, Math.min(23, Number(parts[0]) || 0));
        minutesBox.value = Math.max(0, Math.min(59, Number(parts[1]) || 0));
        root.syncing = false;
    }
    function commit() {
        if (root.syncing) return;
        const text = `${String(hoursBox.value).padStart(2, "0")}:${String(minutesBox.value).padStart(2, "0")}`;
        if (text !== root.value) root.edited(text);
    }
    onValueChanged: sync()
    Component.onCompleted: sync()

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignRight
        Layout.fillWidth: false
        spacing: 2
        StyledSpinBox {
            id: hoursBox
            baseHeight: root.fieldHeight
            from: 0
            to: 23
            padDigits: 2
            wrap: true
            onValueChanged: root.commit()
        }
        StyledText {
            text: ":"
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.normal
            opacity: root.enabled ? 1 : 0.4
        }
        StyledSpinBox {
            id: minutesBox
            baseHeight: root.fieldHeight
            from: 0
            to: 59
            stepSize: root.minuteStep
            padDigits: 2
            onValueChanged: root.commit()
        }
    }
}
