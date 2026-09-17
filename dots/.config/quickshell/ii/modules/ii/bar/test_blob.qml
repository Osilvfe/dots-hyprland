import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Blobs

FloatingWindow {
    id: root
    title: "Rust Fluid Blobs Morphing Test"
    width: 680
    height: 480
    color: "#1e1e2e"

    // 引入 BlobGroup
    BlobGroup {
        id: blobGroup
        color: "#89b4fa"
        smoothing: smoothSlider.value
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        Text {
            text: "Caelestia Fluid Blobs (Rust Engine) Sandbox"
            color: "#cdd6f4"
            font.pixelSize: 18
            font.bold: true
        }

        Text {
            text: "拖动右侧的方形靠近左侧静止方块，观察接触前水滴般的融合粘连（Metaball smin）；快速拖动时观察果冻弹性拉伸。"
            color: "#a6adc8"
            font.pixelSize: 13
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        // 交互画布区域
        Item {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true

            Rectangle {
                anchors.fill: parent
                color: "#181825"
                radius: 12
                border.color: "#313244"
                border.width: 1
            }

            // 静止的左侧形体
            BlobRect {
                id: fixedRect
                group: blobGroup
                x: 100
                y: canvas.height / 2 - 60
                width: 120
                height: 120
                radius: 24

                Text {
                    anchors.centerIn: parent
                    text: "固定节点"
                    color: "#11111b"
                    font.bold: true
                }
            }

            // 可拖动的交互形体（带物理拉伸与速度形变）
            BlobRect {
                id: dragRect
                group: blobGroup
                x: 320
                y: canvas.height / 2 - 60
                width: 120
                height: 120
                radius: 24
                deformScale: 0.0008

                Text {
                    anchors.centerIn: parent
                    text: "拖我融合"
                    color: "#11111b"
                    font.bold: true
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    drag.target: dragRect
                    drag.minimumX: 20
                    drag.maximumX: canvas.width - dragRect.width - 20
                    drag.minimumY: 20
                    drag.maximumY: canvas.height - dragRect.height - 20
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }

        // 控制条
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: "流体平滑度 (smoothing / k): " + Math.round(smoothSlider.value) + "px"
                color: "#cdd6f4"
                font.pixelSize: 13
            }

            Slider {
                id: smoothSlider
                Layout.fillWidth: true
                from: 8
                to: 80
                value: 36
            }

            Button {
                text: "自动来回穿梭动效"
                onClicked: {
                    anim.running = !anim.running
                }
            }
        }
    }

    // 自动往返动画测试流体形变
    SequentialAnimation {
        id: anim
        loops: Animation.Infinite
        NumberAnimation {
            target: dragRect
            property: "x"
            from: 360
            to: 180
            duration: 900
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: dragRect
            property: "x"
            from: 180
            to: 360
            duration: 900
            easing.type: Easing.InOutQuad
        }
    }
}
