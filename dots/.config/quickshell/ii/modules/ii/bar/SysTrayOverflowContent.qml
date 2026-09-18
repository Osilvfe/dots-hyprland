pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property list<var> unpinnedItems: TrayService.unpinnedItems

    readonly property real contentWidth: trayOverflowLayout.implicitWidth + 24
    readonly property real contentHeight: trayOverflowLayout.implicitHeight + 20

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    GridLayout {
        id: trayOverflowLayout
        anchors.centerIn: parent
        columns: Math.max(1, Math.ceil(Math.sqrt(root.unpinnedItems.length)))
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: root.unpinnedItems

            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                Layout.fillHeight: false
                Layout.fillWidth: false
            }
        }
    }
}
