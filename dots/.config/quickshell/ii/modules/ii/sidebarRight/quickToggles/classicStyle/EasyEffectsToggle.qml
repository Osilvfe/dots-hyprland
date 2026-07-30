import qs.modules.common.widgets
import qs
import qs.services
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Hyprland

QuickToggleButton {
    id: root
    visible: EasyEffects.available
    toggled: EasyEffects.active
    buttonIcon: "instant_mix"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    onClicked: {
        EasyEffects.toggle()
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "jamesdsp"])
        GlobalStates.sidebarRightOpen = false
    }

    StyledToolTip {
        text: "JamesDSP | Right-click to configure"
    }
}
