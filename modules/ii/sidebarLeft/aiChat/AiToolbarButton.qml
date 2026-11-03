import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Action button of the Intelligence toolbar: icon + short label, tooltip with the details
RippleButton {
    id: root
    property string symbol
    property string label
    property string tooltipText: label
    property bool showLabel: true

    implicitHeight: 32
    topPadding: 0
    bottomPadding: 0
    implicitWidth: row.implicitWidth + 2 * horizontalPadding
    horizontalPadding: showLabel ? 10 : 8
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    contentItem: RowLayout {
        id: row
        spacing: 5
        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: root.symbol
            iconSize: Appearance.font.pixelSize.larger
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
        StyledText {
            visible: root.showLabel
            Layout.alignment: Qt.AlignVCenter
            Layout.bottomMargin: 2 // font metrics: caps sit ~1px low without it
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        }
    }

    StyledToolTip {
        text: root.tooltipText
    }
}
