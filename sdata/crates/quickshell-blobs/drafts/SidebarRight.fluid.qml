import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Caelestia.Blobs

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth

    PanelWindow {
        id: panelWindow

        property real offsetScale: GlobalStates.sidebarRightOpen ? 0.0 : 1.0
        visible: GlobalStates.sidebarRightOpen || offsetScale < 0.99

        Behavior on offsetScale {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutBack
                easing.overshoot: 0.8
            }
        }

        function hide() {
            GlobalStates.sidebarRightOpen = false;
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        onVisibleChanged: {
            if (visible && GlobalStates.sidebarRightOpen) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else if (!GlobalStates.sidebarRightOpen) {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        // 流体形态渲染群组
        BlobGroup {
            id: sidebarBlobGroup
            color: Appearance.colors.colLayer0
            smoothing: 28.0
        }

        // 滑动与物理变形容器
        Item {
            id: animatedContainer
            anchors.fill: parent
            x: width * panelWindow.offsetScale
            opacity: 1.0 - panelWindow.offsetScale * 0.4

            // 流体形态背景 (BlobRect 由 Rust 动力学引擎实时计算形变与 SDF 距离场)
            BlobRect {
                id: sidebarBlobBg
                group: sidebarBlobGroup
                anchors {
                    fill: parent
                    margins: Appearance.sizes.hyprlandGapsOut
                    leftMargin: Appearance.sizes.elevationMargin
                }
                radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1
                deformScale: 0.0004
            }

            // 侧边栏内容（同步应用果冻物理拉伸矩阵）
            Loader {
                id: sidebarContentLoader
                active: GlobalStates.sidebarRightOpen || Config?.options.sidebar.keepRightSidebarLoaded || panelWindow.offsetScale < 0.99
                anchors {
                    fill: parent
                    margins: Appearance.sizes.hyprlandGapsOut
                    leftMargin: Appearance.sizes.elevationMargin
                }
                width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

                transform: Matrix4x4 {
                    matrix: sidebarBlobBg.deformMatrix
                }

                focus: GlobalStates.sidebarRightOpen
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        panelWindow.hide();
                    }
                }

                sourceComponent: SidebarRightContent {}
            }
        }
    }


    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }
}
