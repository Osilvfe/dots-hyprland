pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Blobs

PanelWindow {
    id: rootWindow

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

    // 严谨对齐 Hyprland gaps (5px) 与顶栏高度 (40px)
    readonly property real gapsOut: 5.0
    readonly property real barHeight: 40.0
    readonly property real frameRadius: 23.0

    // 边框几何尺寸 (顶栏直接内嵌于 borderTop 中)
    property real frameLeft: gapsOut
    property real frameRight: gapsOut
    property real frameTop: barHeight + gapsOut  // 45px
    property real frameBottom: gapsOut          // 5px
    property real smoothingVal: 34.0            // 流体融合平滑度

    // 抽屉展开状态 (0.0: 收起, 1.0: 展开)
    property real drawerOffsetScale: 0.0

    Behavior on drawerOffsetScale {
        NumberAnimation {
            duration: 350
            easing.type: Easing.OutBack
            easing.overshoot: 0.6
        }
    }

    // 核心鼠标穿透遮罩：中间主工作区彻底挖空直通桌面窗口！
    mask: Region {
        id: screenMask

        // 中间主工作区挖空区域
        x: rootWindow.frameLeft
        y: rootWindow.frameTop
        width: Math.max(10, rootWindow.width - rootWindow.frameLeft - rootWindow.frameRight)
        height: Math.max(10, rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom)
        intersection: Intersection.Xor

        // 顶栏区域（保留输入交互）
        Region {
            x: 0
            y: 0
            width: rootWindow.width
            height: rootWindow.frameTop
        }

        // 控制面板区域（保留输入交互）
        Region {
            x: controlCard.x
            y: controlCard.y
            width: controlCard.width
            height: controlCard.height
        }

        // 抽屉面板区域（保留输入交互）
        Region {
            x: drawerPanel.x
            y: drawerPanel.y
            width: drawerPanel.width
            height: drawerPanel.height
        }
    }

    // ==========================================
    // 核心流体渲染群组 (所有元素在同个 GPU UBO 中粘连)
    // ==========================================
    BlobGroup {
        id: fluidBlobGroup
        color: "#181825" // Catppuccin Mantle / Material 3 基础层
        smoothing: rootWindow.smoothingVal
    }

    // 1. 全屏一体化环绕内框 (顶部 45px 包含顶栏实体底色)
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

        readonly property real targetWidth: 420
        // 面板顶部直接紧接在顶栏下方，展示最强烈的边缘水滴粘连效果
        readonly property real targetHeight: rootWindow.height - rootWindow.frameTop - rootWindow.frameBottom - 16

        width: targetWidth
        height: targetHeight

        // 从右边缘向左滑入桌面
        x: rootWindow.width - (targetWidth + rootWindow.frameRight) * rootWindow.drawerOffsetScale - rootWindow.frameRight
        y: rootWindow.frameTop + 8

        radius: 20
        deformScale: 0.0006

        // 抽屉内部卡片内容
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            clip: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                Text {
                    text: "Fluid Drawer (内嵌一体化抽屉)"
                    color: "#cdd6f4"
                    font.pixelSize: 18
                    font.bold: true
                }

                Text {
                    text: "现在顶栏与全屏外框在【同一个绘图表面】中！\n请观察：抽屉滑出时，抽屉顶部边缘与顶栏下沿之间发生的【物理水滴粘连】（Metaball smin 融合）。两者不再是割裂的独立贴片，而是浑然一体！"
                    color: "#a6adc8"
                    font.pixelSize: 13
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: "#313244"
                }

                Text {
                    text: "快捷设置模拟项"
                    color: "#89b4fa"
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        text: "Wi-Fi: 已连接"
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "蓝牙: 开启"
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        text: "勿休眠模式"
                        Layout.fillWidth: true
                    }
                    Button {
                        text: "夜间护眼"
                        Layout.fillWidth: true
                    }
                }

                Item { Layout.fillHeight: true }

                Button {
                    text: "收起抽屉"
                    Layout.fillWidth: true
                    onClicked: rootWindow.drawerOffsetScale = 0.0
                }
            }
        }
    }

    // ==========================================
    // 3. 真正内嵌于流体内衬之中的完整顶栏 (Authentic BarContent)
    // ==========================================
    Item {
        id: integratedTopBar
        x: 0
        y: 0
        width: parent.width
        height: rootWindow.barHeight // 40px

        // 直接复用仓库中拥有全部歌词/工作区/托盘/电量功能的真实顶栏内容！
        Loader {
            anchors.fill: parent
            sourceComponent: Component {
                // 优先加载本地真实 BarContent
                Item {
                    anchors.fill: parent
                    Loader {
                        anchors.fill: parent
                        source: "../bar/BarContent.qml"
                    }
                }
            }
        }
    }


    // ==========================================
    // 4. 调试与参数调节卡片
    // ==========================================
    Rectangle {
        id: controlCard
        width: 480
        height: 130
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: rootWindow.frameBottom + 20
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
                    text: "Caelestia 真正一体化（顶栏 + 四周边框 + 抽屉）沙盒"
                    color: "#cdd6f4"
                    font.bold: true
                    font.pixelSize: 13
                }
                Item { Layout.fillWidth: true }
                Button {
                    text: "退出测试"
                    onClicked: Qt.quit()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "液体平滑粘连 (smoothing): " + Math.round(smoothSlider.value) + "px"
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
                    text: rootWindow.drawerOffsetScale > 0.5 ? "收起侧边抽屉" : "展开侧边抽屉 (观察顶栏连接处液态拉伸)"
                    Layout.fillWidth: true
                    onClicked: {
                        rootWindow.drawerOffsetScale = rootWindow.drawerOffsetScale > 0.5 ? 0.0 : 1.0;
                    }
                }
            }
        }
    }
}
