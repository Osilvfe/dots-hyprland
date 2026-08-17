import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 260

    component MaterialSectionHeader: WindowDialogSectionHeader {
        color: Appearance.colors.colPrimary
        font.pixelSize: Appearance.font.pixelSize.smaller
    }

    component Section: Rectangle {
        id: sectionRoot
        default property alias content: inner.data

        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: inner.implicitHeight + inner.anchors.margins * 2
        width: parent.width
        radius: 12

        Column {
            id: inner
            anchors.fill: parent
            anchors.margins: 8
            width: parent.width
            spacing: 4
        }
    }

    WindowDialogTitle {
        text: Translation.tr("Clash Verge Rev")
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Column {
        spacing: 8
        Layout.fillWidth: true

        MaterialSectionHeader {
            text: Translation.tr("Proxy")
        }

        Section {
            ConfigSwitch {
                anchors {
                    left: parent.left
                    right: parent.right
                }
                iconSize: Appearance.font.pixelSize.larger
                buttonIcon: "language"
                text: Translation.tr("System proxy")
                checked: ClashVerge.systemProxy
                onCheckedChanged: {
                    if (checked !== ClashVerge.systemProxy)
                        ClashVerge.setSystemProxy(checked)
                }
            }

            ConfigSwitch {
                anchors {
                    left: parent.left
                    right: parent.right
                }
                iconSize: Appearance.font.pixelSize.larger
                buttonIcon: "vpn_lock"
                text: Translation.tr("TUN mode")
                checked: ClashVerge.tun
                onCheckedChanged: {
                    if (checked !== ClashVerge.tun)
                        ClashVerge.setTun(checked)
                }
            }
        }
    }

    WindowDialogButtonRow {
        Layout.margins: 4
        Layout.fillWidth: true

        DialogButton {
            buttonText: Translation.tr("Open app")
            onClicked: ClashVerge.openApp()
        }

        Item {
            Layout.fillWidth: true
        }

        DialogButton {
            buttonText: Translation.tr("Done")
            onClicked: root.dismiss()
            colBackground: Appearance.colors.colPrimary
            colText: Appearance.colors.colOnPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
        }
    }
}
