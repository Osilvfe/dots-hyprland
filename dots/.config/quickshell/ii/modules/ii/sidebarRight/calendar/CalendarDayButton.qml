import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: button
    property string day
    property int isToday
    property bool bold
    property string lunar: ""

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38
    implicitHeight: 42

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small

    contentItem: Item {
        anchors.fill: parent

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: lunar ? 2 : 8
            text: day
            horizontalAlignment: Text.AlignHCenter
            font.weight: bold ? Font.DemiBold : Font.Normal
            color: (isToday == 1) ? Appearance.m3colors.m3onPrimary :
                (isToday == 0) ? Appearance.colors.colOnLayer1 :
                Appearance.colors.colOutlineVariant

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            visible: lunar !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            text: lunar
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 9
            color: (isToday == 1) ? (ColorUtils.transparentize(Appearance.m3colors.m3onPrimary, 0.5)) :
                (isToday == 0) ? ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.4) :
                ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.6)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }
}
