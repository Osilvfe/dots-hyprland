import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Auto-rotate")
    statusText: Orientation.autoRotate 
        ? Translation.tr("Auto") 
        : (Orientation.isPortrait ? Translation.tr("Portrait") : Translation.tr("Landscape"))

    toggled: Orientation.autoRotate || Orientation.isPortrait
    icon: Orientation.autoRotate 
        ? "screen_rotation" 
        : (Orientation.isPortrait ? "screen_lock_portrait" : "screen_lock_landscape")

    mainAction: () => {
        Orientation.toggleLandscapePortrait()
    }
    altAction: () => {
        Orientation.toggleAutoRotate()
    }

    tooltipText: Translation.tr("Screen rotation toggle")
}
