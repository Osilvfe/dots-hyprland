pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()

    IconToolbarButton {
        text: "activity_zone"
        toggled: root.selectionMode === RegionSelection.SelectionMode.RectCorners
        onClicked: root.selectionMode = RegionSelection.SelectionMode.RectCorners
        StyledToolTip {
            text: Translation.tr("矩形选区")
        }
    }

    IconToolbarButton {
        text: "gesture"
        toggled: root.selectionMode === RegionSelection.SelectionMode.Circle
        onClicked: root.selectionMode = RegionSelection.SelectionMode.Circle
        StyledToolTip {
            text: Translation.tr("圆形选区")
        }
    }

    IconToolbarButton {
        text: "colorize"
        onClicked: {
            Quickshell.execDetached(["bash", "-c", "hyprpicker -a"]);
            root.dismiss();
        }
        StyledToolTip {
            text: Translation.tr("取色器")
        }
    }

    IconToolbarButton {
        text: "fullscreen"
        onClicked: {
            Quickshell.execDetached(["bash", "-c", "grim - | wl-copy"]);
            root.dismiss();
        }
        StyledToolTip {
            text: Translation.tr("全屏截图")
        }
    }

    IconToolbarButton {
        text: "gif"
        onClicked: {
            Quickshell.execDetached(["bash", "-c", Directories.recordScriptPath + " --gif"]);
            root.dismiss();
        }
        StyledToolTip {
            text: Translation.tr("录制 GIF")
        }
    }

    IconToolbarButton {
        text: "mic"
        onClicked: {
            Quickshell.execDetached(["bash", "-c",
                "DIR=$HOME/Music; mkdir -p \"$DIR\"; " +
                "notify-send 'Starting recording' 'mic_$(date +%Y-%m-%d_%H.%M.%S).wav' -a 'Recorder' & " +
                "if pgrep -x pw-record; then qs -c ii ipc call recording status none 2>/dev/null; pkill -x pw-record && notify-send 'Recording Stopped' 'Stopped' -a 'Recorder'; " +
                "else qs -c ii ipc call recording status mic 2>/dev/null; pw-record --target=\"$(pactl get-default-source)\" \"$DIR/mic_$(date +%Y-%m-%d_%H.%M.%S).wav\"; fi"]);
            root.dismiss();
        }
        StyledToolTip {
            text: Translation.tr("录麦克风")
        }
    }

    IconToolbarButton {
        text: "speaker"
        onClicked: {
            Quickshell.execDetached(["bash", "-c",
                "DIR=$HOME/Music; mkdir -p \"$DIR\"; " +
                "notify-send 'Starting recording' 'system_$(date +%Y-%m-%d_%H.%M.%S).wav' -a 'Recorder' & " +
                "if pgrep -x parec; then qs -c ii ipc call recording status none 2>/dev/null; pkill -x parec && notify-send 'Recording Stopped' 'Stopped' -a 'Recorder'; " +
                "else SRC=$(pactl get-default-sink).monitor; " +
                "qs -c ii ipc call recording status system 2>/dev/null; parec --device=\"$SRC\" --file-format=wav \"$DIR/system_$(date +%Y-%m-%d_%H.%M.%S).wav\"; fi"]);
            root.dismiss();
        }
        StyledToolTip {
            text: Translation.tr("录系统声音")
        }
    }
}
