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
    property bool detach: false
    property bool pin: false
    function toggleDetach(): void { root.detach = !root.detach; }
    function togglePin(): void { root.pin = !root.pin; }

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

                readonly property bool sidebarLeftOpen: GlobalStates.sidebarLeftOpen
                property real drawerLeftOffsetScale: sidebarLeftOpen ? 1.0 : 0.0

                readonly property bool overviewOpen: GlobalStates.overviewOpen
                property real overviewOffsetScale: overviewOpen ? 1.0 : 0.0

                // 动画运行状态指示器 (用于开启 GPU 纹理加速)
                readonly property bool isAnimating: drawerOffsetAnim.running || drawerLeftOffsetAnim.running || overviewOffsetAnim.running

                Behavior on drawerOffsetScale {
                    NumberAnimation {
                        id: drawerOffsetAnim
                        duration: 350
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.6
                    }
                }

                Behavior on drawerLeftOffsetScale {
                    NumberAnimation {
                        id: drawerLeftOffsetAnim
                        duration: 350
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.6
                    }
                }

                Behavior on overviewOffsetScale {
                    NumberAnimation {
                        id: overviewOffsetAnim
                        duration: 320
                        easing.type: Easing.OutBack
                        easing.overshoot: 0.5
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

                    // 2. 右侧抽屉面板区域：展开状态下覆盖最终静止目标矩形，动画期间零高频重绘
                    Region {
                        x: rootWindow.width - drawerPanel.targetWidth - rootWindow.frameRight
                        y: drawerPanel.y
                        width: rootWindow.sidebarOpen ? drawerPanel.targetWidth : 0
                        height: rootWindow.sidebarOpen ? drawerPanel.targetHeight : 0
                    }

                    // 3. 左侧抽屉面板区域：展开状态下覆盖最终静止目标矩形
                    Region {
                        x: rootWindow.frameLeft
                        y: drawerLeftPanel.y
                        width: rootWindow.sidebarLeftOpen ? drawerLeftPanel.targetWidth : 0
                        height: rootWindow.sidebarLeftOpen ? drawerLeftPanel.targetHeight : 0
                    }

                    // 4. 搜索面板区域：展开状态下覆盖最终静止目标矩形
                    Region {
                        x: overviewBottomPanel.targetX
                        y: rootWindow.height - rootWindow.frameBottom - 640
                        width: rootWindow.overviewOpen ? overviewBottomPanel.targetWidth : 0
                        height: rootWindow.overviewOpen ? 640 : 0
                    }

                    // 5. 抽屉或搜索展开时，覆盖中央工作区遮罩用于点击收起
                    Region {
                        x: rootWindow.frameLeft + (rootWindow.sidebarLeftOpen ? drawerLeftPanel.targetWidth : 0)
                        y: rootWindow.frameTop
                        width: (rootWindow.sidebarOpen || rootWindow.sidebarLeftOpen || rootWindow.overviewOpen) ?
                               Math.max(0, rootWindow.width - rootWindow.frameLeft - rootWindow.frameRight 
                                           - (rootWindow.sidebarOpen ? drawerPanel.targetWidth : 0)
                                           - (rootWindow.sidebarLeftOpen ? drawerLeftPanel.targetWidth : 0)) : 0
                        height: (rootWindow.sidebarOpen || rootWindow.sidebarLeftOpen || rootWindow.overviewOpen) ?
                                Math.max(0, rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom) : 0
                    }
                }

                // 点击抽屉外部空白区域自动收起抽屉与搜索
                MouseArea {
                    anchors.fill: parent
                    enabled: (rootWindow.sidebarOpen && rootWindow.drawerOffsetScale > 0.05) ||
                             (rootWindow.sidebarLeftOpen && rootWindow.drawerLeftOffsetScale > 0.05) ||
                             (rootWindow.overviewOpen && rootWindow.overviewOffsetScale > 0.05)
                    z: 50
                    onClicked: {
                        GlobalStates.sidebarRightOpen = false;
                        GlobalStates.sidebarLeftOpen = false;
                        GlobalStates.overviewOpen = false;
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

                // 2. 右侧滑出的抽屉纯流体浮岛胶囊（独立浮岛，上下流出空间让着色器充分拉出双向波浪桥）
                BlobRect {
                    id: drawerPanel
                    group: fluidBlobGroup
                    z: 60

                    readonly property real targetWidth: Appearance.sizes.sidebarWidth
                    // 浮岛胶囊高度：上下留出开阔净空，让着色器在上下两端充分拉出圆滑波浪颈部！
                    readonly property real targetHeight: Math.min(840, Math.max(520, Math.round((rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom) * 0.74)))
                    readonly property real targetX: rootWindow.width - rootWindow.frameRight - targetWidth
                    // 收起时退到屏幕之外 smoothVal + 15 距离，彻底杜绝边框边缘的 smin 凸起鼓包
                    readonly property real hiddenX: rootWindow.width + rootWindow.smoothVal + 15

                    width: targetWidth
                    height: targetHeight

                    // 从屏幕外向左波浪涌入
                    x: targetX + (hiddenX - targetX) * (1.0 - rootWindow.drawerOffsetScale)
                    // 垂直居中于顶栏下沿与底座之间，上下均拥有 100~200px 广阔流体场
                    y: rootWindow.frameTop + (rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom - targetHeight) / 2

                    // 完整的四角大圆角胶囊
                    radius: 28
                    // 动态左侧双圆角溶出渐变（刚展开时如液滴被拔出边框）
                    topLeftRadius: Math.max(0, Math.min(1, rootWindow.drawerOffsetScale / 0.35)) * 28
                    bottomLeftRadius: Math.max(0, Math.min(1, rootWindow.drawerOffsetScale / 0.35)) * 28

                    deformScale: 0.00001
                    stiffness: 220.0
                    damping: 14.0
                }

                // 3. 左侧滑出的抽屉纯流体浮岛胶囊（与右翼对称独立浮岛，上下留出开阔净空拉出双向波浪桥）
                BlobRect {
                    id: drawerLeftPanel
                    group: fluidBlobGroup
                    z: 60

                    readonly property real targetWidth: Appearance.sizes.sidebarWidth
                    readonly property real targetHeight: Math.min(840, Math.max(520, Math.round((rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom) * 0.74)))
                    readonly property real targetX: rootWindow.frameLeft
                    // 收起时退到屏幕之外 smoothVal + 15 距离，彻底杜绝边框边缘的 smin 凸起鼓包
                    readonly property real hiddenX: -targetWidth - rootWindow.smoothVal - 15

                    width: targetWidth
                    height: targetHeight

                    // 从屏幕外向右波浪涌入
                    x: targetX - (targetX - hiddenX) * (1.0 - rootWindow.drawerLeftOffsetScale)
                    // 垂直居中于顶栏下沿与底座之间，上下均拥有 100~200px 广阔流体场
                    y: rootWindow.frameTop + (rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom - targetHeight) / 2

                    // 完整的四角大圆角胶囊
                    radius: 28
                    // 动态右侧双圆角溶出渐变（刚展开时如液滴被拔出边框）
                    topRightRadius: Math.max(0, Math.min(1, rootWindow.drawerLeftOffsetScale / 0.35)) * 28
                    bottomRightRadius: Math.max(0, Math.min(1, rootWindow.drawerLeftOffsetScale / 0.35)) * 28

                    deformScale: 0.00001
                    stiffness: 220.0
                    damping: 14.0
                }

                // 4. 底部搜索流体抽屉胶囊 (参考 Caelestia 底部抽屉体系，自底沿向上滑入)
                BlobRect {
                    id: overviewBottomPanel
                    group: fluidBlobGroup
                    z: 60

                    readonly property real targetWidth: Math.min(680, rootWindow.width - 80)
                    readonly property real targetHeight: Math.min(640, Math.max(80, GlobalStates.overviewContentHeight))
                    readonly property real targetX: (rootWindow.width - targetWidth) / 2
                    readonly property real targetY: rootWindow.height - rootWindow.frameBottom - targetHeight
                    readonly property real hiddenY: rootWindow.height + rootWindow.smoothVal + 15

                    width: targetWidth
                    height: targetHeight

                    x: targetX
                    y: targetY + (hiddenY - targetY) * (1.0 - rootWindow.overviewOffsetScale)

                    // 四角大圆角胶囊
                    radius: 28
                    topLeftRadius: 28
                    topRightRadius: 28
                    // 底部圆角在拔出过程中动态平滑溶出
                    bottomLeftRadius: Math.max(0, Math.min(1, rootWindow.overviewOffsetScale / 0.35)) * 28
                    bottomRightRadius: Math.max(0, Math.min(1, rootWindow.overviewOffsetScale / 0.35)) * 28

                    deformScale: 0.00001
                    stiffness: 240.0
                    damping: 15.0
                }

                // ==========================================
                // 3. 独立上层侧边栏交互与内容层（后渲染/延后淡入，与底层流体浮岛联动）
                // ==========================================
                // 右侧抽屉内容
                Item {
                    id: drawerContentLayer
                    z: 65
                    x: drawerPanel.x
                    y: drawerPanel.y
                    width: drawerPanel.width
                    height: drawerPanel.height

                    // 视觉核心：后渲染/延后渐入感知
                    // 前半程 (0~0.35) 纯净展示流体双向波浪拔出与粘连，后半程 (0.35~1.0) 平滑浮现内容
                    opacity: Math.max(0, Math.min(1, (rootWindow.drawerOffsetScale - 0.35) / 0.65))
                    visible: rootWindow.drawerOffsetScale > 0.001

                    // 动画期间开启 GPU 纹理缓存加速
                    layer.enabled: rootWindow.isAnimating

                    // 挂载完整原生 SidebarRightContent (预热常驻)
                    Loader {
                        id: sidebarLoader
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        active: true
                        source: "../sidebarRight/SidebarRightContent.qml"
                    }
                }

                // 左侧抽屉内容
                Item {
                    id: drawerLeftContentLayer
                    z: 65
                    x: drawerLeftPanel.x
                    y: drawerLeftPanel.y
                    width: drawerLeftPanel.width
                    height: drawerLeftPanel.height

                    // 视觉核心：后渲染/延后渐入感知
                    opacity: Math.max(0, Math.min(1, (rootWindow.drawerLeftOffsetScale - 0.35) / 0.65))
                    visible: rootWindow.drawerLeftOffsetScale > 0.001

                    // 动画期间开启 GPU 纹理缓存加速
                    layer.enabled: rootWindow.isAnimating

                    // 挂载完整原生 SidebarLeftContent (预热常驻)
                    Loader {
                        id: sidebarLeftLoader
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        active: true
                        Component.onCompleted: {
                            setSource("../sidebarLeft/SidebarLeftContent.qml", {
                                "scopeRoot": root
                            });
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

    // 兼容原生 sidebarLeft IPC 与全局快捷键
    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }

        function close(): void {
            GlobalStates.sidebarLeftOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"
        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftOpen"
        description: "Opens left sidebar on press"
        onPressed: {
            GlobalStates.sidebarLeftOpen = true;
        }
    }

    GlobalShortcut {
        name: "sidebarLeftClose"
        description: "Closes left sidebar on press"
        onPressed: {
            GlobalStates.sidebarLeftOpen = false;
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
