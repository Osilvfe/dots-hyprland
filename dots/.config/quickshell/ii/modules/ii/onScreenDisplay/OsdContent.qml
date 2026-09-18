pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string currentIndicator: GlobalStates.osdIndicator ?? "volume"
    property string protectionMessage: GlobalStates.osdProtectionMessage ?? ""

    readonly property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "gamma",
            sourceUrl: "indicators/GammaIndicator.qml"
        },
    ]

    implicitWidth: contentColumnLayout.implicitWidth
    implicitHeight: contentColumnLayout.implicitHeight

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: GlobalStates.osdVolumeOpen = false
    }

    Column {
        id: contentColumnLayout
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4

        Loader {
            id: osdIndicatorLoader
            anchors.horizontalCenter: parent.horizontalCenter
            source: root.indicators.find(i => i.id === root.currentIndicator)?.sourceUrl
        }

        Item {
            id: protectionMessageWrapper
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.protectionMessage !== ""
            implicitHeight: protectionMessageBackground.implicitHeight
            implicitWidth: protectionMessageBackground.implicitWidth
            opacity: root.protectionMessage !== "" ? 1 : 0

            StyledRectangularShadow {
                target: protectionMessageBackground
            }

            Rectangle {
                id: protectionMessageBackground
                anchors.centerIn: parent
                color: Appearance.m3colors.m3error
                property real padding: 10
                implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                radius: Appearance.rounding.normal

                RowLayout {
                    id: protectionMessageRowLayout
                    anchors.centerIn: parent
                    MaterialSymbol {
                        id: protectionMessageIcon
                        text: "dangerous"
                        iconSize: Appearance.font.pixelSize.hugeass
                        color: Appearance.m3colors.m3onError
                    }
                    StyledText {
                        id: protectionMessageTextWidget
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.m3colors.m3onError
                        wrapMode: Text.Wrap
                        text: root.protectionMessage
                    }
                }
            }
        }
    }
}
