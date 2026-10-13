import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets

/**
 * Single-select color swatch array for custom colors.
 * Same interaction design as ColorSelectionArray (ring + swatch morph
 * with selection animation), but each option carries its own color
 * instead of a theme role.
 *
 * options: list of { value: string, color: string, rainbow?: bool,
 *                    icon?: string, displayName?: string }
 */
Row {
    id: root
    spacing: 10

    property string currentValue: ""
    property var options: []
    property real swatchSize: 40
    signal selected(string newValue)

    Repeater {
        model: root.options
        delegate: Item {
            id: slot
            required property var modelData
            readonly property bool isSelected: root.currentValue === slot.modelData.value

            implicitWidth: root.swatchSize
            implicitHeight: root.swatchSize

            Rectangle {
                id: ring
                anchors.centerIn: parent
                width: slot.isSelected ? parent.width : parent.width - 8
                height: slot.isSelected ? parent.height : parent.height - 8
                radius: slot.isSelected ? Appearance.rounding.normal : width / 2
                color: "transparent"
                border.width: slot.isSelected ? 2 : 0
                border.color: Appearance.colors.colOnLayer0

                Behavior on radius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            Rectangle {
                id: swatch
                anchors.centerIn: parent
                width: slot.isSelected ? parent.width - 8 : parent.width - 8
                height: slot.isSelected ? parent.height - 8 : parent.height - 8
                radius: slot.isSelected ? Appearance.rounding.normal - 4 : width / 2
                color: (slot.modelData.rainbow ?? false) ? "transparent" : slot.modelData.color
                readonly property bool isRainbow: (slot.modelData.rainbow ?? false)

                Behavior on radius {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // Rainbow swatch: native Qt Quick Shapes gradient clipped by the
                // rounded rect path. (The old Qt5Compat ConicalGradient inside a
                // layer + OpacityMask crashed the shell when its window was torn
                // down on reload / color scheme change.)
                Loader {
                    anchors.fill: parent
                    active: swatch.isRainbow
                    sourceComponent: Shape {
                        id: rainbowShape
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: -1
                            fillGradient: ConicalGradient {
                                centerX: rainbowShape.width / 2
                                centerY: rainbowShape.height / 2
                                angle: 90
                                GradientStop { position: 0.0;   color: "#f44336" }
                                GradientStop { position: 0.166; color: "#9c27b0" }
                                GradientStop { position: 0.333; color: "#2196f3" }
                                GradientStop { position: 0.5;   color: "#4caf50" }
                                GradientStop { position: 0.666; color: "#ffeb3b" }
                                GradientStop { position: 0.833; color: "#ff9800" }
                                GradientStop { position: 1.0;   color: "#f44336" }
                            }
                            PathRectangle {
                                x: 0
                                y: 0
                                width: rainbowShape.width
                                height: rainbowShape.height
                                radius: Math.min(swatch.radius, rainbowShape.width / 2, rainbowShape.height / 2)
                            }
                        }
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: (slot.modelData.icon ?? "").length > 0
                text: slot.modelData.icon ?? ""
                iconSize: root.swatchSize / 2 + 2
                color: Appearance.colors.colOnLayer0
            }

            MouseArea {
                id: slotHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selected(slot.modelData.value)

                StyledToolTip {
                    visible: slotHover.containsMouse && (slot.modelData.displayName ?? "").length > 0
                    text: slot.modelData.displayName ?? ""
                }
            }
        }
    }
}
