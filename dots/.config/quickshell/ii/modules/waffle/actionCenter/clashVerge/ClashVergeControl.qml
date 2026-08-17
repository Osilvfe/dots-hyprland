import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks
import qs.modules.waffle.actionCenter

Item {
    id: root

    WPanelPageColumn {
        anchors.fill: parent

        BodyRectangle {
            implicitHeight: 400
            implicitWidth: 50

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 4
                spacing: 4

                HeaderRow {
                    Layout.fillWidth: true
                    title: Translation.tr("Clash Verge Rev")
                }

                StyledFlickable {
                    id: flickable
                    Layout.fillHeight: true
                    Layout.fillWidth: true

                    contentHeight: contentLayout.implicitHeight
                    contentWidth: width
                    clip: true
                    bottomMargin: 12

                    ClashVergeOptions {
                        id: contentLayout
                        width: flickable.width
                    }
                }
            }
        }

        WPanelSeparator {}

        FooterRectangle {
            WButton {
                id: openAppButton
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                }
                implicitHeight: 40
                implicitWidth: contentItem.implicitWidth + 30
                color: "transparent"

                onClicked: ClashVerge.openApp()

                contentItem: Item {
                    anchors.centerIn: parent
                    implicitWidth: buttonText.implicitWidth
                    WText {
                        id: buttonText
                        anchors.centerIn: parent
                        text: Translation.tr("Open Clash Verge Rev")
                        color: openAppButton.pressed ? Looks.colors.fg : Looks.colors.fg1
                    }
                }
            }
        }
    }

    component ClashVergeOptions: ColumnLayout {
        spacing: 10

        SectionText {
            text: Translation.tr("Proxy")
        }

        ToggleItem {
            name: Translation.tr("System proxy")
            description: Translation.tr("For browsers and apps that honor the OS proxy")
            iconName: "globe-shield"
            checked: ClashVerge.systemProxy
            onCheckedChanged: {
                if (checked !== ClashVerge.systemProxy)
                    ClashVerge.setSystemProxy(checked)
            }
        }

        ToggleItem {
            name: Translation.tr("TUN mode")
            description: Translation.tr("Route all traffic through a virtual NIC")
            iconName: "shield-lock"
            checked: ClashVerge.tun
            onCheckedChanged: {
                if (checked !== ClashVerge.tun)
                    ClashVerge.setTun(checked)
            }
        }
    }
}
