import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.modules.ii.onScreenDisplay

OsdValueIndicator {
    id: root

    icon: "keyboard"
    name: Translation.tr("Keyboard Layout")
    value: 0
    valueText: HyprlandXkb.currentLayoutName
    showProgressBar: false
    stackNameValue: true
}
