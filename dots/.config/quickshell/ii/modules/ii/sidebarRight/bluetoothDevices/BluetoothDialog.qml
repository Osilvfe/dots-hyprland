import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import Quickshell

WindowDialog {
    id: root
    backgroundHeight: 600

    component MaterialSectionHeader: WindowDialogSectionHeader {
        color: Appearance.colors.colPrimary
        font.pixelSize: Appearance.font.pixelSize.small
        Layout.fillWidth: true
        Layout.leftMargin: 12
    }

    component Section: Rectangle {
        id: sectionRoot
        default property alias content: inner.data

        color: Appearance.colors.colSurfaceContainerHighest
        implicitHeight: inner.implicitHeight + inner.anchors.margins * 2
        Layout.fillWidth: true
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
        text: Translation.tr("Bluetooth devices")
        anchors.horizontalCenter: parent.horizontalCenter
    }
    Text {
        text: Translation.tr("Tap to connect or disconnect a device")
        font.pixelSize: Appearance.font.pixelSize.small
        anchors.horizontalCenter: parent.horizontalCenter
        color: Appearance.colors.colOnSurface
        Layout.topMargin: -8
    }
    StyledIndeterminateProgressBar {
        Layout.maximumWidth: 160
        visible: Bluetooth.defaultAdapter?.discovering ?? false
        anchors.horizontalCenter: parent.horizontalCenter
        Layout.topMargin: -4
        Layout.bottomMargin: -8
    }
    Flickable {
        Layout.fillHeight: true
        Layout.fillWidth: true
        clip: true
        contentHeight: deviceColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: deviceColumn
            width: parent.width
            spacing: 8

            MaterialSectionHeader {
                visible: namedRepeater.count > 0
                text: Translation.tr("Named devices")
            }
            Section {
                visible: namedRepeater.count > 0
                Repeater {
                    id: namedRepeater
                    model: ScriptModel {
                        values: BluetoothStatus.namedDeviceList
                    }
                    BluetoothDeviceItem {
                        required property BluetoothDevice modelData
                        device: modelData
                        width: parent?.width ?? 0
                    }
                }
            }

            MaterialSectionHeader {
                visible: unnamedRepeater.count > 0
                text: Translation.tr("Unnamed devices")
            }
            Section {
                visible: unnamedRepeater.count > 0
                Repeater {
                    id: unnamedRepeater
                    model: ScriptModel {
                        values: BluetoothStatus.unnamedDeviceList
                    }
                    BluetoothDeviceItem {
                        required property BluetoothDevice modelData
                        device: modelData
                        width: parent?.width ?? 0
                    }
                }
            }
        }
    }
    WindowDialogButtonRow {
        Layout.margins: 4

        DialogButton {
            buttonText: Translation.tr("Details")
            onClicked: {
                Quickshell.execDetached(["bash", "-c", `${Config.options.apps.bluetooth}`]);
                GlobalStates.sidebarRightOpen = false;
            }
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
