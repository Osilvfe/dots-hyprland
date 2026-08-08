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
    property string holiday: ""
    property string holidayOff: ""
    property string workday: ""

    Layout.fillWidth: false
    Layout.fillHeight: false
    implicitWidth: 38
    implicitHeight: 46

    toggled: (isToday == 1)
    buttonRadius: Appearance.rounding.small

    contentItem: Item {
        anchors.fill: parent

        // Corner badge: 休 (holiday off) or 班 (make-up workday)
        StyledText {
            visible: holidayOff !== "" || workday !== ""
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.rightMargin: 2
            text: workday !== "" ? workday : holidayOff
            font.pixelSize: 8
            font.weight: Font.DemiBold
            color: workday !== ""
                ? Appearance.colors.colError
                : (isToday == 1) ? Appearance.m3colors.m3onPrimary : Appearance.colors.colPrimary

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: (lunar || holiday) ? 2 : 8
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

        // Festival name (only on the actual festival day)
        StyledText {
            visible: holiday !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 20
            text: holiday
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 8
            color: (isToday == 1) ? (ColorUtils.transparentize(Appearance.m3colors.m3onPrimary, 0.3)) :
                (isToday == 0) ? Appearance.colors.colPrimary :
                ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.7)

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }

        // Lunar date (shown when no festival name)
        StyledText {
            visible: holiday === "" && lunar !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 20
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
