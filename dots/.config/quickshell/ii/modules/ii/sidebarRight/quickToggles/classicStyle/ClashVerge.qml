import qs
import qs.modules.common.widgets
import qs.modules.common.models.quickToggles
import QtQuick
import Quickshell

QuickToggleButton {
    id: root
    visible: toggleModel.available
    toggled: toggleModel.toggled
    buttonIcon: toggleModel.icon

    property ClashVergeToggle toggleModel: ClashVergeToggle {}

    onClicked: toggleModel.mainAction()

    altAction: toggleModel.altAction

    StyledToolTip {
        text: toggleModel.tooltipText
    }
}
