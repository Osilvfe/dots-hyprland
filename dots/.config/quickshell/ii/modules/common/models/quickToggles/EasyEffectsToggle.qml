import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("JamesDSP")

    available: EasyEffects.available
    toggled: EasyEffects.active
    icon: "graphic_eq"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    mainAction: () => {
        EasyEffects.toggle()
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "jamesdsp"])
        GlobalStates.sidebarRightOpen = false
    }

    tooltipText: Translation.tr("JamesDSP | Right-click to configure")
}
