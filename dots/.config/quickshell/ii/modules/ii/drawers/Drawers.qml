pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Caelestia.Blobs

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    // 多显示器适配
    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = Config.options.bar.screenList;
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.includes(screen.name));
        }

        LazyLoader {
            id: drawerLoader
            active: !GlobalStates.screenLocked
            required property ShellScreen modelData

            component: Scope {
                id: monitorScope

                // 1. 顶栏单向排他避让表面 (仅让普通窗口避让顶栏高度)
                PanelWindow {
                    id: barExclusionWindow
                    screen: drawerLoader.modelData
                    WlrLayershell.namespace: "quickshell:drawers_bar_exclusion"
                    WlrLayershell.layer: WlrLayer.Top

                    anchors {
                        top: true
                        left: true
                        right: true
                    }

                    implicitHeight: 1
                    exclusiveZone: Appearance.sizes.baseBarHeight + Appearance.sizes.hyprlandGapsOut
                    color: "transparent"

                    // 空 Region：鼠标事件 100% 穿透，不拦截任何交互
                    mask: Region {}
                }

                // 2. 全屏一体化流体画框与抽屉交互主表面
                PanelWindow {
                    id: rootWindow
                    screen: drawerLoader.modelData

                    color: "transparent"

                    anchors {
                        top: true
                        bottom: true
                        left: true
                        right: true
                    }

                    WlrLayershell.namespace: "quickshell:drawers"
                    WlrLayershell.layer: WlrLayer.Top
                    WlrLayershell.exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0

                // 严谨对齐 Hyprland gaps 与顶栏高度
                readonly property real gapsOut: Appearance.sizes.hyprlandGapsOut
                readonly property real barHeight: Appearance.sizes.baseBarHeight
                readonly property real frameRadius: Appearance.rounding.screenRounding
                readonly property real smoothVal: Config.options.appearance.fluidMorphing.smoothing ?? 34.0

                // 边框几何尺寸 (顶栏直接内嵌于 borderTop 中)
                readonly property real frameLeft: gapsOut
                readonly property real frameRight: gapsOut
                readonly property real frameTop: barHeight + gapsOut
                readonly property real frameBottom: gapsOut

                // 抽屉展开状态联动 GlobalStates
                readonly property bool sidebarOpen: GlobalStates.sidebarRightOpen
                property real drawerOffsetScale: sidebarOpen ? 1.0 : 0.0

                Behavior on drawerOffsetScale {
                    NumberAnimation {
                        duration: 350
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.6
                    }
                }

                // 核心输入遮罩：中间主工作区彻底挖空直通 Hyprland 桌面窗口
                mask: Region {
                    id: screenMask

                    // 1. 中间主工作区挖空区域 (保证窗口点击与穿透)
                    x: rootWindow.frameLeft
                    y: rootWindow.frameTop
                    width: Math.max(10, rootWindow.width - rootWindow.frameLeft - rootWindow.frameRight)
                    height: Math.max(10, rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom)
                    intersection: Intersection.Xor

                    // 2. 顶栏区域（常驻保留输入交互）
                    Region {
                        x: 0
                        y: 0
                        width: rootWindow.width
                        height: rootWindow.frameTop
                    }

                    // 3. 抽屉面板区域（展开时保留输入交互）
                    Region {
                        x: drawerPanel.x
                        y: drawerPanel.y
                        width: drawerPanel.width
                        height: drawerPanel.height
                    }

                    // 4. 抽屉展开时，覆盖中央工作区遮罩用于点击收起
                    Region {
                        x: rootWindow.frameLeft
                        y: rootWindow.frameTop
                        width: rootWindow.drawerOffsetScale > 0.05 ? Math.max(0, rootWindow.width - rootWindow.frameLeft - rootWindow.frameRight - drawerPanel.width) : 0
                        height: rootWindow.drawerOffsetScale > 0.05 ? Math.max(0, rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom) : 0
                    }
                }

                // 点击抽屉外部空白区域自动收起抽屉
                MouseArea {
                    anchors.fill: parent
                    enabled: rootWindow.drawerOffsetScale > 0.05
                    z: 50
                    onClicked: {
                        GlobalStates.sidebarRightOpen = false;
                    }
                }

                // ==========================================
                // 核心流体渲染群组 (所有元素在同个 GPU UBO 中粘连)
                // ==========================================
                BlobGroup {
                    id: fluidBlobGroup
                    color: Appearance.colors.colLayer0
                    smoothing: rootWindow.smoothVal
                }

                // 1. 全屏一体化环绕内框 (顶部包含顶栏实体底色)
                BlobInvertedRect {
                    id: invertedFrame
                    group: fluidBlobGroup
                    anchors.fill: parent

                    radius: rootWindow.frameRadius
                    borderLeft: rootWindow.frameLeft
                    borderRight: rootWindow.frameRight
                    borderTop: rootWindow.frameTop
                    borderBottom: rootWindow.frameBottom
                }

                // 2. 右侧滑出的抽屉面板（与顶栏在同个着色器中无缝粘连）
                BlobRect {
                    id: drawerPanel
                    group: fluidBlobGroup
                    z: 60

                    readonly property real targetWidth: Appearance.sizes.sidebarWidth
                    readonly property real targetHeight: rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom - 8

                    width: targetWidth
                    height: targetHeight

                    // 从右边缘向左滑入桌面
                    x: rootWindow.width - (targetWidth + rootWindow.frameRight) * rootWindow.drawerOffsetScale - rootWindow.frameRight
                    y: rootWindow.frameTop + 4

                    radius: Appearance.rounding.windowRounding
                    deformScale: 0.0006

                    // 挂载完整原生 SidebarRightContent
                    Loader {
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        active: rootWindow.drawerOffsetScale > 0.01 || (Config?.options.sidebar.keepRightSidebarLoaded ?? false)
                        source: "../sidebarRight/SidebarRightContent.qml"
                    }
                }

                // ==========================================
                // 3. 真正内嵌于流体内衬之中的完整顶栏 (Authentic BarContent)
                // ==========================================
                Item {
                    id: integratedTopBar
                    z: 70
                    x: 0
                    y: 0
                    width: parent.width
                    height: rootWindow.barHeight

                    Loader {
                        anchors.fill: parent
                        source: "../bar/BarContent.qml"
                    }
                }
            }
        }
    }
    }

    // 抽屉与一体化流体 IPC 控制通道
    IpcHandler {
        target: "drawers"

        function toggleRight(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function openRight(): void {
            GlobalStates.sidebarRightOpen = true;
        }

        function closeRight(): void {
            GlobalStates.sidebarRightOpen = false;
        }
    }

    // 兼容原生 sidebarRight IPC 与全局快捷键
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

    // 兼容原生 bar IPC 与全局快捷键
    IpcHandler {
        target: "bar"

        function toggle(): void {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }

        function close(): void {
            GlobalStates.barOpen = false;
        }

        function open(): void {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barToggle"
        description: "Toggles bar on press"
        onPressed: {
            GlobalStates.barOpen = !GlobalStates.barOpen;
        }
    }

    GlobalShortcut {
        name: "barOpen"
        description: "Opens bar on press"
        onPressed: {
            GlobalStates.barOpen = true;
        }
    }

    GlobalShortcut {
        name: "barClose"
        description: "Closes bar on press"
        onPressed: {
            GlobalStates.barOpen = false;
        }
    }
}
