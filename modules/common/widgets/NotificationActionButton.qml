import qs.modules.common
import qs.services
import QtQuick
import Quickshell.Services.Notifications

RippleButton {
    id: button
    property string buttonText
    property string iconName: ""
    property string urgency
    readonly property color contentColor: (urgency == NotificationUrgency.Critical) ? Appearance.m3colors.m3onSurfaceVariant : Appearance.m3colors.m3onSurface

    implicitHeight: 34
    leftPadding: 13
    rightPadding: 15
    buttonRadius: Appearance.rounding.small
    colBackground: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer4
    colBackgroundHover: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer4Hover
    colRipple: (urgency == NotificationUrgency.Critical) ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer4Active

    // Icon + label, so every button says what it does. Either part may be empty.
    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight
        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol {
                visible: button.iconName !== ""
                anchors.verticalCenter: parent.verticalCenter
                iconSize: Appearance.font.pixelSize.larger
                color: button.contentColor
                text: button.iconName
            }
            StyledText {
                visible: button.buttonText !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: button.buttonText
                color: button.contentColor
            }
        }
    }
}
