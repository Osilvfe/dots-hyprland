pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Blobs

PanelWindow {
    id: rootWindow

    title: "Caelestia Inverted Frame & Drawer Sandbox"
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    WlrLayershell.namespace: "quickshell:drawers_sandbox"
    WlrLayershell.layer: WlrLayer.Top
    exclusiveZone: 0

    // 边框几何尺寸
    property real frameLeft: 42.0     // 模拟左侧栏或状态栏宽度
    property real frameRight: 14.0    // 右侧边框厚度
    property real frameTop: 14.0      // 顶部边框厚度
    property real frameBottom: 14.0   // 底部边框厚度
    property real frameRadius: 26.0   // 屏幕内凹圆角半径
    property real smoothingVal: 32.0  // 流体融合平滑度

    // 抽屉展开状态 (0.0: 完全收起贴合边缘, 1.0: 完全滑入桌面)
    property real drawerOffsetScale: 0.0

    Behavior on drawerOffsetScale {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutBack
            easing.overshoot: 0.6
        }
    }

    // 核心鼠标事件穿透区域：中间完全挖空（Xor 取反），直通桌面应用！
    mask: Region {
        id: screenMask

        // 中间主工作区挖空区域
        x: rootWindow.frameLeft + 1
        y: rootWindow.frameTop + 1
        width: Math.max(10, rootWindow.width - rootWindow.frameLeft - rootWindow.frameRight - 2)
        height: Math.max(10, rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom - 2)
        intersection: Intersection.Xor

        // 控制面板区域（保留输入）
        Region {
            x: controlCard.x
            y: controlCard.y
            width: controlCard.width
            height: controlCard.height
        }

        // 抽屉面板区域（保留输入）
        Region {
            x: drawerPanel.x
            y: drawerPanel.y
            width: drawerPanel.width
            height: drawerPanel.height
        }
    }

    // 流体形态渲染总控群组 (同一 Group 下的所有形体会通过 GPU SDF 融合)
    BlobGroup {
        id: fluidBlobGroup
        color: "#1e1e2e" // Material 3 / Catppuccin Base 经典色
        smoothing: rootWindow.smoothingVal
    }

    // 1. 屏幕边缘一体化环绕内衬 (Inverted Frame)
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

    // 2. 右侧滑出的抽屉面板（从右边框“生长”拉伸）
    BlobRect {
        id: drawerPanel
        group: fluidBlobGroup

        readonly property real targetWidth: 380
        readonly property real targetHeight: rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom - 40

        width: targetWidth
        height: targetHeight

        // 从屏幕右边缘滑入：0.0 时贴在边缘（凹陷融合），1.0 时完全展开
        x: rootWindow.width - (targetWidth + rootWindow.frameRight) * rootWindow.drawerOffsetScale - rootWindow.frameRight
        y: rootWindow.frameTop + 20

        radius: 22
        deformScale: 0.0006

        // 抽屉内部内容
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 14

                Text {
                    text: "Fluid Drawer Panel"
                    color: "#cdd6f4"
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    text: "注意观察面板左边缘与上方/下方/右方边框之间的凹陷过度（Border Sink Pocket）与流体水润连接，这就是 Caelestia 的一体化精髓！"
                    color: "#a6adc8"
                    font.pixelSize: 13
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }

                Button {
                    text: rootWindow.drawerOffsetScale > 0.5 ? "收起抽屉" : "展开抽屉"
                    Layout.fillWidth: true
                    onClicked: {
                        rootWindow.drawerOffsetScale = rootWindow.drawerOffsetScale > 0.5 ? 0.0 : 1.0;
                    }
                }
            }
        }
    }

    // 3. 悬浮的控制卡片（位于屏幕中间偏上，方便操作与调试）
    Rectangle {
        id: controlCard
        width: 460
        height: 140
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: rootWindow.frameTop + 24
        color: "#181825"
        radius: 16
        border.color: "#313244"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Caelestia 一体化内衬画框 (Inverted Frame) 测试"
                    color: "#cdd6f4"
                    font.bold: true
                    font.pixelSize: 14
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: "关闭测试"
                    onClicked: Qt.quit()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "流体平滑度 (smoothing): " + Math.round(smoothSlider.value) + "px"
                    color: "#bac2de"
                    font.pixelSize: 12
                }
                Slider {
                    id: smoothSlider
                    Layout.fillWidth: true
                    from: 10
                    to: 60
                    value: rootWindow.smoothingVal
                    onValueChanged: rootWindow.smoothingVal = value
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    text: rootWindow.drawerOffsetScale > 0.5 ? "收起侧边抽屉" : "展开侧边抽屉"
                    Layout.fillWidth: true
                    onClicked: {
                        rootWindow.drawerOffsetScale = rootWindow.drawerOffsetScale > 0.5 ? 0.0 : 1.0;
                    }
                }
                Button {
                    text: "切换左侧栏加厚 (42px / 14px)"
                    onClicked: {
                        rootWindow.frameLeft = rootWindow.frameLeft > 20 ? 14 : 42;
                    }
                }
            }
        }
    }
}
