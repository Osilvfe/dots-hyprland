import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property bool pinned: Config.options?.osk.pinnedOnStartup ?? false

    component OskControlButton: GroupButton { // Pin button
        baseWidth: 40
        baseHeight: 40
        clickedWidth: baseWidth
        clickedHeight: baseHeight + 10
        buttonRadius: Appearance.rounding.normal
    }

    Loader {
        id: oskLoader
        active: GlobalStates.oskOpen
        onActiveChanged: {
            if (!oskLoader.active) {
                VirtualKeyboard.releaseAllKeys();
            }
        }
        
        sourceComponent: PanelWindow { // Window
            id: oskRoot
            visible: oskLoader.active && !GlobalStates.screenLocked

            anchors {
                bottom: true
                left: true
                right: true
            }

            function hide() {
                GlobalStates.oskOpen = false
            }
            exclusiveZone: root.pinned ? implicitHeight - Appearance.sizes.hyprlandGapsOut : 0
            implicitWidth: oskBackground.width + Appearance.sizes.elevationMargin * 2
            implicitHeight: oskBackground.height + Appearance.sizes.elevationMargin * 2
            WlrLayershell.namespace: "quickshell:osk"
            WlrLayershell.layer: WlrLayer.Overlay
            // Hyprland 0.49: Focus is always exclusive and setting this breaks mouse focus grab
            // WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            mask: Region {
                item: oskBackground
            }

            // Make it usable with other panels
            Component.onCompleted: {
                GlobalFocusGrab.addPersistent(oskRoot);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removePersistent(oskRoot);
            }

            // Background
            StyledRectangularShadow {
                target: oskBackground
            }
            Rectangle {
                id: oskBackground
                anchors.centerIn: parent
                color: Appearance.colors.colLayer0
                radius: Appearance.rounding.windowRounding
                property real padding: 10
                implicitWidth: oskColLayout.implicitWidth + padding * 2
                implicitHeight: oskColLayout.implicitHeight + padding * 2

                Keys.onPressed: (event) => { // Esc to close
                    if (event.key === Qt.Key_Escape) {
                        oskRoot.hide()
                    }
                }

                ColumnLayout {
                    id: oskColLayout
                    anchors.centerIn: parent
                    spacing: 4

                    // Swipe-down / tap dismiss handle
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        Layout.bottomMargin: 2
                        implicitWidth: 80
                        implicitHeight: 14

                        Rectangle {
                            anchors.centerIn: parent
                            width: 48
                            height: 4
                            radius: 2
                            color: handleMouseArea.containsMouse ? Appearance.colors.colOutline : Appearance.colors.colOutlineVariant
                            Behavior on color {
                                ColorAnimation { duration: 150 }
                            }
                        }

                        MouseArea {
                            id: handleMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            property real startY: 0
                            onPressed: mouse => {
                                startY = mouse.y;
                            }
                            onPositionChanged: mouse => {
                                if (mouse.y - startY > 15) {
                                    oskRoot.hide();
                                }
                            }
                            onClicked: {
                                oskRoot.hide();
                            }
                        }
                    }

                    RowLayout {
                        id: oskRowLayout
                        spacing: 5
                    VerticalButtonGroup {
                        OskControlButton { // Pin button
                            toggled: root.pinned
                            downAction: () => root.pinned = !root.pinned
                            contentItem: MaterialSymbol {
                                text: "keep"
                                horizontalAlignment: Text.AlignHCenter
                                iconSize: Appearance.font.pixelSize.larger
                                color: root.pinned ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer0
                            }
                        }
                        OskControlButton {
                            onClicked: () => {
                                oskRoot.hide()
                            }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "keyboard_hide"
                                iconSize: Appearance.font.pixelSize.larger
                            }
                        }
                    }
                    Rectangle {
                        Layout.topMargin: 20
                        Layout.bottomMargin: 20
                        Layout.fillHeight: true
                        implicitWidth: 1
                        color: Appearance.colors.colOutlineVariant
                    }
                    OskContent {
                        id: oskContent
                        Layout.fillWidth: true
                    }
                }
            }
            }

        }
    }

    Loader {
        id: edgeTriggerLoader
        active: !GlobalStates.oskOpen && !GlobalStates.screenLocked && (TabletMode.isTabletMode || (Config.options?.osk?.bottomEdgeSwipe ?? false))
        sourceComponent: PanelWindow {
            id: edgeTriggerWindow
            WlrLayershell.namespace: "quickshell:osk_edge_trigger"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusiveZone: 0
            color: "transparent"

            anchors {
                bottom: true
                left: true
                right: true
            }
            implicitHeight: 14

            // Handle indicator shown in tablet mode
            Rectangle {
                anchors.centerIn: parent
                width: 72
                height: 4
                radius: 2
                visible: TabletMode.isTabletMode
                color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)
                opacity: edgeMouseArea.containsMouse ? 1 : 0.6
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }

            MouseArea {
                id: edgeMouseArea
                anchors.fill: parent
                hoverEnabled: true
                property real startY: 0
                property bool swiping: false

                onPressed: mouse => {
                    startY = mouse.y;
                    swiping = true;
                }
                onPositionChanged: mouse => {
                    if (swiping && (startY - mouse.y > 10 || mouse.y < -5)) {
                        swiping = false;
                        GlobalStates.oskOpen = true;
                    }
                }
                onReleased: {
                    swiping = false;
                }
                onClicked: {
                    if (TabletMode.isTabletMode) {
                        GlobalStates.oskOpen = true;
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osk"

        function toggle(): void {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }

        function close(): void {
            GlobalStates.oskOpen = false
        }

        function open(): void {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskToggle"
        description: "Toggles on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = !GlobalStates.oskOpen;
        }
    }

    GlobalShortcut {
        name: "oskOpen"
        description: "Opens on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = true
        }
    }

    GlobalShortcut {
        name: "oskClose"
        description: "Closes on screen keyboard on press"

        onPressed: {
            GlobalStates.oskOpen = false
        }
    }

}
