import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

RippleButton {
    id: button

    required default property Item content
    property bool extraActiveCondition: false

    implicitHeight: Math.max(content.implicitHeight, (TabletMode.isTabletMode ? 32 : 26))
    implicitWidth: implicitHeight
    contentItem: content

}
