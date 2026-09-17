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

                // 1. 四周画框固定排他避让 (对齐 Caelestia ExclusionZone 体系)
                // 顶部：45px (顶栏 40px + 外边距 5px)
                PanelWindow {
                    screen: drawerLoader.modelData
                    WlrLayershell.namespace: "quickshell:drawers_top_exclusion"
                    WlrLayershell.layer: WlrLayer.Top
                    anchors { top: true; left: true; right: true }
                    implicitHeight: 1
                    exclusiveZone: Appearance.sizes.baseBarHeight + Appearance.sizes.hyprlandGapsOut
                    color: "transparent"
                    mask: Region {}
                }

                // 左侧：5px (画框左侧固定边距)
                PanelWindow {
                    screen: drawerLoader.modelData
                    WlrLayershell.namespace: "quickshell:drawers_left_exclusion"
                    WlrLayershell.layer: WlrLayer.Top
                    anchors { left: true; top: true; bottom: true }
                    implicitWidth: 1
                    exclusiveZone: Appearance.sizes.hyprlandGapsOut
                    color: "transparent"
                    mask: Region {}
                }

                // 右侧：5px (画框右侧固定边距，无论抽屉是否展开均恒定为 5px，抽屉纯悬浮浮于窗口之上！)
                PanelWindow {
                    screen: drawerLoader.modelData
                    WlrLayershell.namespace: "quickshell:drawers_right_exclusion"
                    WlrLayershell.layer: WlrLayer.Top
                    anchors { right: true; top: true; bottom: true }
                    implicitWidth: 1
                    exclusiveZone: Appearance.sizes.hyprlandGapsOut
                    color: "transparent"
                    mask: Region {}
                }

                // 底部：5px (画框底部固定边距)
                PanelWindow {
                    screen: drawerLoader.modelData
                    WlrLayershell.namespace: "quickshell:drawers_bottom_exclusion"
                    WlrLayershell.layer: WlrLayer.Top
                    anchors { bottom: true; left: true; right: true }
                    implicitHeight: 1
                    exclusiveZone: Appearance.sizes.hyprlandGapsOut
                    color: "transparent"
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

                // 动画运行状态指示器 (用于开启 GPU 纹理加速)
                readonly property bool isAnimating: drawerOffsetAnim.running

                Behavior on drawerOffsetScale {
                    NumberAnimation {
                        id: drawerOffsetAnim
                        duration: rootWindow.sidebarOpen ? 500 : 380
                        easing.type: Easing.BezierSpline
                        // Caelestia Expressive Wave: 展开时过冲至 1.21 水波回荡归位；收起时 Expressive Decel 快速平滑吸入
                        easing.bezierCurve: rootWindow.sidebarOpen
                            ? [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]
                            : [0.4, 0.0, 0.2, 1.0, 1.0, 1.0]
                    }
                }

                // 核心输入遮罩：静态解耦设计，运动全程 0 次 Wayland IPC 提交，彻底根除高频重绘掉帧
                mask: Region {
                    id: screenMask

                    // 1. 顶栏区域（常驻保留输入交互）
                    Region {
                        x: 0
                        y: 0
                        width: rootWindow.width
                        height: rootWindow.frameTop
                    }

                    // 2. 抽屉面板区域：展开状态下覆盖最终静止目标矩形，动画期间零高频重绘
                    Region {
                        x: rootWindow.width - drawerPanel.targetWidth - rootWindow.frameRight
                        y: drawerPanel.y
                        width: rootWindow.sidebarOpen ? drawerPanel.targetWidth : 0
                        height: rootWindow.sidebarOpen ? drawerPanel.targetHeight : 0
                    }

                    // 3. 抽屉展开时，覆盖中央工作区遮罩用于点击收起
                    Region {
                        x: rootWindow.frameLeft
                        y: rootWindow.frameTop
                        width: rootWindow.sidebarOpen ? Math.max(0, rootWindow.width - rootWindow.frameLeft - rootWindow.frameRight - drawerPanel.targetWidth) : 0
                        height: rootWindow.sidebarOpen ? Math.max(0, rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom) : 0
                    }
                }

                // 点击抽屉外部空白区域自动收起抽屉
                MouseArea {
                    anchors.fill: parent
                    enabled: rootWindow.sidebarOpen && rootWindow.drawerOffsetScale > 0.05
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
                    readonly property real targetHeight: rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom
                    readonly property real targetX: rootWindow.width - rootWindow.frameRight - targetWidth
                    // 收起时退到屏幕之外 smoothVal + 15 距离，彻底杜绝边框边缘的 smin 凸起鼓包
                    readonly property real hiddenX: rootWindow.width + rootWindow.smoothVal + 15

                    width: targetWidth
                    height: targetHeight

                    // 从屏幕外向左波浪涌入
                    x: targetX + (hiddenX - targetX) * (1.0 - rootWindow.drawerOffsetScale)
                    // 顶端无缝贴合顶栏下沿，最大化 Liquid Bridge 流体粘连桥
                    y: rootWindow.frameTop

                    radius: Appearance.rounding.windowRounding
                    // 动态左下圆角溶出渐变（刚展开时如液滴被拔出边框）
                    bottomLeftRadius: Math.max(0, Math.min(1, rootWindow.drawerOffsetScale / 0.35)) * Appearance.rounding.windowRounding

                    deformScale: 0.0006
                    stiffness: 220.0
                    damping: 14.0

                    // 抽屉内容容器：果冻张量拉伸联动 + GPU 纹理层加速
                    Item {
                        id: drawerContentContainer
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true

                        // 动画期间开启 GPU 纹理缓存加速，杜绝子组件逐帧重排
                        layer.enabled: rootWindow.isAnimating

                        // 核心流体联动：内容跟随 Rust 动力学弹簧应变张量一起产生果冻水波形变！
                        transform: Matrix4x4 {
                            matrix: drawerPanel.deformMatrix
                        }

                        // 挂载完整原生 SidebarRightContent (预热常驻，避免展开首帧卡顿)
                        Loader {
                            id: sidebarLoader
                            anchors.fill: parent
                            active: true
                            visible: rootWindow.drawerOffsetScale > 0.001
                            source: "../sidebarRight/SidebarRightContent.qml"
                        }
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

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

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
