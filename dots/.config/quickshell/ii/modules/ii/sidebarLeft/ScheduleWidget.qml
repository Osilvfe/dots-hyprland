import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    implicitWidth: timeW + 7 * (cellW + gap) + gap + 16
    implicitHeight: headerH + 6 * (cellH + gap) + gap + 16

    property var scheduleItems: []
    property var timeHeaders: []
    property var headers: ["一", "二", "三", "四", "五", "六", "日"]

    property int timeW: 40
    property int cellW: 52
    property int cellH: 52
    property int headerH: 24
    property int gap: 4

    function getColor(id) {
        var c = [
            Appearance.colors.colPrimaryContainer,
            Appearance.colors.colSecondaryContainer,
            Appearance.colors.colTertiaryContainer,
            ColorUtils.transparentize(Appearance.colors.colErrorContainer, 0.6),
            Appearance.colors.colLayer2Hover,
        ]
        return c[id % c.length]
    }

    function getTextColor(id) {
        var c = [
            Appearance.colors.colOnPrimaryContainer,
            Appearance.colors.colOnSecondaryContainer,
            Appearance.colors.colOnTertiaryContainer,
            Appearance.colors.colOnErrorContainer,
            Appearance.colors.colOnSurfaceVariant,
        ]
        return c[id % c.length]
    }

    property string filePath: Directories.scheduleCache

    FileView {
        id: scheduleFile
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            try {
                var text = scheduleFile.text()
                if (text.trim()) {
                    var p = JSON.parse(text)
                    root.timeHeaders = p.timeHeaders || []
                    root.scheduleItems = p.scheduleItems || []
                }
            } catch(e) {
                console.log("schedule:", e)
            }
        }
        onLoadFailed: function(error) {
            console.log("schedule load fail:", error, "path:", path)
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 8
        clip: true
        contentWidth: root.timeW + 7 * (root.cellW + root.gap) + root.gap
        contentHeight: Math.max(root.headerH + (root.timeHeaders.length || 4) * (root.cellH + root.gap) + root.gap, 200)
        boundsBehavior: Flickable.StopAtBounds

        Item {
            width: flick.contentWidth
            height: flick.contentHeight

            StyledText {
                x: 0; y: 0
                width: root.timeW; height: root.headerH
                text: "时间"
                font.pixelSize: 10; font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }

            Row {
                x: root.timeW + root.gap; y: 0
                spacing: root.gap
                Repeater {
                    model: root.headers
                    Rectangle {
                        width: root.cellW; height: root.headerH; color: "transparent"
                        StyledText {
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: 10; font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }
            }

            Column {
                x: 0; y: root.headerH + root.gap
                spacing: root.gap
                Repeater {
                    model: Math.max(root.timeHeaders.length, 4)
                    Rectangle {
                        width: root.timeW; height: root.cellH; color: "transparent"
                        StyledText {
                            anchors.centerIn: parent
                            text: root.timeHeaders[index] ? root.timeHeaders[index].replace(" - ", "\n") : (index + 1).toString()
                            font.pixelSize: 9
                            color: Appearance.colors.colOutline
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Repeater {
                model: root.scheduleItems
                Rectangle {
                    x: root.timeW + root.gap + modelData.col * (root.cellW + root.gap)
                    y: root.headerH + root.gap + modelData.row * (root.cellH + root.gap)
                    width: root.cellW
                    height: root.cellH * modelData.rowSpan + root.gap * (modelData.rowSpan - 1)
                    radius: 6
                    color: modelData.isEmpty ? "transparent" : root.getColor(modelData.colorId)

                    StyledText {
                        anchors.fill: parent
                        anchors.margins: 3
                        text: modelData.isEmpty ? "" : modelData.text
                        color: root.getTextColor(modelData.colorId)
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
