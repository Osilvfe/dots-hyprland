import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Tablet Mode")
    statusText: TabletMode.isTabletMode ? Translation.tr("Tablet") : Translation.tr("Desktop")

    toggled: TabletMode.isTabletMode
    icon: TabletMode.isTabletMode ? "tablet_android" : "laptop"

    mainAction: () => {
        TabletMode.toggle()
    }

    tooltipText: Translation.tr("Tablet mode toggle")
}
