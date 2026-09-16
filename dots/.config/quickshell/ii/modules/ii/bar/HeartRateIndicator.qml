import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

MouseArea {
    id: root

    implicitWidth: pillBackground.implicitWidth
    implicitHeight: Appearance.sizes.barHeight
    width: implicitWidth
    height: implicitHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            HeartRate.resetStats();
        } else {
            HeartRate.toggleMock();
        }
    }

    Rectangle {
        id: pillBackground
        anchors.centerIn: parent
        implicitHeight: 18
        implicitWidth: contentRow.implicitWidth + 12
        radius: Appearance.rounding.full
        color: ColorUtils.transparentize(HeartRate.zoneColor, 0.85)
        border.width: 1
        border.color: ColorUtils.transparentize(HeartRate.zoneColor, 0.45)

        Behavior on color {
            ColorAnimation { duration: 250 }
        }
        Behavior on border.color {
            ColorAnimation { duration: 250 }
        }

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            spacing: 3

            MaterialSymbol {
                id: heartIcon
                Layout.alignment: Qt.AlignVCenter
                fill: 1
                text: "favorite"
                iconSize: 12
                color: HeartRate.zoneColor
                transformOrigin: Item.Center

                Behavior on color {
                    ColorAnimation { duration: 250 }
                }

                SequentialAnimation {
                    id: heartbeatAnim
                    running: (HeartRate.connected || HeartRate.isMock || HeartRate.bpm > 0)
                    loops: Animation.Infinite

                    NumberAnimation {
                        target: heartIcon
                        property: "scale"
                        to: 1.30
                        duration: 110
                        easing.type: Easing.OutQuad
                    }
                    NumberAnimation {
                        target: heartIcon
                        property: "scale"
                        to: 1.0
                        duration: 150
                        easing.type: Easing.InOutQuad
                    }
                    PauseAnimation {
                        duration: Math.max(80, (60000 / Math.max(30, HeartRate.bpm > 0 ? HeartRate.bpm : 70)) - 260)
                    }
                }
            }

            StyledText {
                id: bpmText
                Layout.alignment: Qt.AlignVCenter
                font.pixelSize: 12
                font.weight: Font.DemiBold
                text: HeartRate.bpm > 0 ? String(HeartRate.bpm) : "--"
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    HeartRatePopup {
        id: hrPopup
        hoverTarget: root
    }
}
