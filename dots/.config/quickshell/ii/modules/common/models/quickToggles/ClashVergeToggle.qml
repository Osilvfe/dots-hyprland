import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Clash Verge Rev")
    icon: ClashVerge.tun ? "vpn_lock" : "vpn_key"
    available: ClashVerge.available
    toggled: ClashVerge.active
    statusText: ClashVerge.statusText
    hasMenu: true
    tooltipText: Translation.tr("Clash Verge Rev | Right-click to configure")

    mainAction: () => {
        ClashVerge.toggle()
    }
    altAction: () => {
        ClashVerge.openApp()
    }

    Component.onCompleted: ClashVerge.refresh()
}
