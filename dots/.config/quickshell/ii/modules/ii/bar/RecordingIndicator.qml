pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property color colText: rightSidebarButton?.colText ?? Appearance.colors.colOnSurface

    readonly property string recordingType: GlobalStates.recordingType
    readonly property bool recordingActive: root.recordingType !== "none"
    property real nowMs: Date.now()
    readonly property string iconText: switch (root.recordingType) {
        case "screen": return "screen_record";
        case "gif": return "gif";
        case "mic": return "mic";
        case "system": return "speaker";
        default: return "record";
    }
    readonly property string elapsedText: {
        if (!root.recordingActive) return "";
        const total = Math.floor((root.nowMs - GlobalStates.recordingStartedAt) / 1000);
        const mm = String(Math.floor(total / 60)).padStart(2, "0");
        const ss = String(total % 60).padStart(2, "0");
        return `${mm}:${ss}`;
    }

    implicitWidth: contentRow.visible ? contentRow.implicitWidth : 0
    implicitHeight: contentRow.implicitHeight

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    function stopRecording(): void {
        stopProcess.running = false;
        stopProcess.running = true;
    }

    Process {
        id: stopProcess
        command: ["bash", "-c",
            "if pgrep -x wf-recorder >/dev/null 2>&1; then pkill -INT wf-recorder; " +
            "elif pgrep -x pw-record >/dev/null 2>&1; then pkill -x pw-record; " +
            "elif pgrep -x parec >/dev/null 2>&1; then pkill -x parec; fi; " +
            "qs -c ii ipc call recording status none 2>/dev/null; " +
            "notify-send 'Recording Stopped' 'Stopped' -a 'Recorder' &"]
    }

    Row {
        id: contentRow
        visible: root.recordingActive
        spacing: 5

        Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: root.recordingType === "mic" || root.recordingType === "system"
                ? Appearance.colors.colPrimary : "#ff5252"
        }

        MaterialSymbol {
            text: root.iconText
            iconSize: Appearance.font.pixelSize.larger
            color: root.colText
        }

        StyledText {
            text: root.elapsedText
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.monospace
            color: root.colText
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.stopRecording()
    }
}
