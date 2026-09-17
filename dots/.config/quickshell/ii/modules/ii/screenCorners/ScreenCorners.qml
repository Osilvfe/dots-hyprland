pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Caelestia.Blobs

Scope {
    id: screenCorners
    readonly property Toplevel activeWindow: ToplevelManager.activeToplevel

    function openSidebarForCorner(isLeft) {
        if (isLeft)
            GlobalStates.sidebarLeftOpen = true;
        else
            GlobalStates.sidebarRightOpen = true;
    }

    function toggleSidebarForCorner(isLeft) {
        if (isLeft)
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        else
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
    }

    // 单屏幕全屏流体环绕内框
    component FluidFramePanelWindow: PanelWindow {
        id: frameWindow

        required property var screenMonitor
        required property bool isFullscreen

        color: "transparent"
        WlrLayershell.namespace: "quickshell:fluidFrame"
        WlrLayershell.layer: WlrLayer.Top
        exclusiveZone: 0

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // 全屏过渡与显隐进度 (0.0: 完全全屏避让/隐藏, 1.0: 正常展示)
        property real activeProgress: isFullscreen ? 0.0 : 1.0

        Behavior on activeProgress {
            NumberAnimation {
                duration: 250
                easing.type: Easing.OutCubic
            }
        }

        // 几何规范对齐
        readonly property real gapsOut: Appearance.sizes.hyprlandGapsOut
        readonly property bool isBarBottom: Config?.options?.bar?.bottom ?? false
        readonly property bool isBarCornerFloating: (Config?.options?.bar?.cornerStyle ?? 0) === 1
        readonly property real barHeight: Appearance.sizes.barHeight

        // 动态边框厚度计算
        readonly property real targetTop: isBarBottom ? gapsOut : (barHeight + (isBarCornerFloating ? gapsOut : 0))
        readonly property real targetBottom: isBarBottom ? (barHeight + (isBarCornerFloating ? gapsOut : 0)) : gapsOut
        readonly property real curBorderTop: targetTop * activeProgress
        readonly property real curBorderBottom: targetBottom * activeProgress
        readonly property real curBorderLeft: gapsOut * activeProgress
        readonly property real curBorderRight: gapsOut * activeProgress
        readonly property real curRadius: Appearance.rounding.screenRounding * activeProgress

        // 核心：工作区穿透遮罩（Xor 取反，中间区域 100% 直通应用程序）
        mask: Region {
            id: screenMask

            // 中间主工作区挖空区域
            x: Math.round(frameWindow.curBorderLeft)
            y: Math.round(frameWindow.curBorderTop)
            width: Math.max(10, Math.round(frameWindow.width - frameWindow.curBorderLeft - frameWindow.curBorderRight))
            height: Math.max(10, Math.round(frameWindow.height - frameWindow.curBorderTop - frameWindow.curBorderBottom))
            intersection: Intersection.Xor

            // 四角手势区域：若开启了角触发手势，保留输入区域
            Region {
                id: cornerTriggers
                // 四周 5px 内自然不被挖空，已包含在外围输入层
            }
        }

        // 流体形态渲染群组 (绑定系统自适应 Material 3 配色)
        BlobGroup {
            id: frameBlobGroup
            color: Appearance.colors.colLayer0
            smoothing: 28.0
        }

        // 屏幕边缘流体一体化内衬
        BlobInvertedRect {
            id: invertedRect
            group: frameBlobGroup
            anchors.fill: parent

            radius: frameWindow.curRadius
            borderTop: frameWindow.curBorderTop
            borderBottom: frameWindow.curBorderBottom
            borderLeft: frameWindow.curBorderLeft
            borderRight: frameWindow.curBorderRight
            opacity: frameWindow.activeProgress
        }

        // 四角边缘滑动与手势触发器 (继承自原版 ScreenCorners)
        Loader {
            id: cornerInteractionLoader
            active: (Config?.options?.sidebar?.cornerOpen?.enable ?? false) && !frameWindow.isFullscreen
            anchors.fill: parent

            sourceComponent: Item {
                anchors.fill: parent

                // 左上 / 左下角 (呼出左侧栏)
                MouseArea {
                    width: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    height: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    anchors.top: parent.top
                    anchors.left: parent.left
                    hoverEnabled: true
                    onEntered: if (Config.options.sidebar.cornerOpen.clickless) screenCorners.openSidebarForCorner(true)
                    onPressed: screenCorners.toggleSidebarForCorner(true)
                }
                MouseArea {
                    width: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    height: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    hoverEnabled: true
                    onEntered: if (Config.options.sidebar.cornerOpen.clickless) screenCorners.openSidebarForCorner(true)
                    onPressed: screenCorners.toggleSidebarForCorner(true)
                }

                // 右上 / 右下角 (呼出右侧栏)
                MouseArea {
                    width: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    height: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    anchors.top: parent.top
                    anchors.right: parent.right
                    hoverEnabled: true
                    onEntered: if (Config.options.sidebar.cornerOpen.clickless) screenCorners.openSidebarForCorner(false)
                    onPressed: screenCorners.toggleSidebarForCorner(false)
                }
                MouseArea {
                    width: Config.options.sidebar.cornerOpen.cornerRegionWidth
                    height: Config.options.sidebar.cornerOpen.cornerRegionHeight
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    hoverEnabled: true
                    onEntered: if (Config.options.sidebar.cornerOpen.clickless) screenCorners.openSidebarForCorner(false)
                    onPressed: screenCorners.toggleSidebarForCorner(false)
                }
            }
        }
    }

    // 为每个物理屏幕实例化全屏流体画框
    Variants {
        model: Quickshell.screens

        Scope {
            id: monitorScope
            required property var modelData
            property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

            // 全屏检测
            property list<HyprlandWorkspace> workspacesForMonitor: Hyprland.workspaces.values.filter(workspace => workspace.monitor && workspace.monitor.name == monitor?.name)
            property var activeWorkspaceWithFullscreen: workspacesForMonitor.filter(workspace => ((workspace.toplevels.values.filter(window => window.wayland?.fullscreen)[0] != undefined) && workspace.active))[0]
            property bool fullscreen: activeWorkspaceWithFullscreen != undefined

            FluidFramePanelWindow {
                screen: monitorScope.modelData
                screenMonitor: monitorScope.monitor
                isFullscreen: monitorScope.fullscreen
            }
        }
    }
}
