pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property int transform: 0
    property bool isPortrait: transform === 1 || transform === 3
    property bool autoRotate: false

    readonly property string stateFilePath: `${StandardPaths.standardLocations(StandardPaths.RuntimeLocation)[0]}/hypr_rotation`
    readonly property string autoPidFilePath: `${StandardPaths.standardLocations(StandardPaths.RuntimeLocation)[0]}/hypr_autorotate.pid`

    FileView {
        id: stateFile
        path: FileUtils.trimFileProtocol(root.stateFilePath)
        onLoaded: {
            const val = parseInt(stateFile.text().trim());
            if (!isNaN(val) && val >= 0 && val <= 3) {
                root.transform = val;
            }
        }
    }

    FileWatch {
        path: FileUtils.trimFileProtocol(root.stateFilePath)
        onFileChanged: {
            stateFile.reload();
        }
    }

    function setTransform(val: int): void {
        const script = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/rotate_screen.sh`;
        Quickshell.execDetached(["bash", script, val.toString()]);
    }

    function rotateNext(): void {
        const script = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/rotate_screen.sh`;
        Quickshell.execDetached(["bash", script, "next"]);
    }

    function toggleLandscapePortrait(): void {
        const script = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/rotate_screen.sh`;
        Quickshell.execDetached(["bash", script, "toggle"]);
    }

    function toggleAutoRotate(): void {
        const script = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/rotate_screen.sh`;
        Quickshell.execDetached(["bash", script, "auto-toggle"]);
        root.autoRotate = !root.autoRotate;
    }

    IpcHandler {
        target: "orientation"

        function set(val: int): void {
            root.transform = val;
        }

        function toggle(): void {
            root.toggleLandscapePortrait();
        }

        function next(): void {
            root.rotateNext();
        }

        function auto(): void {
            root.toggleAutoRotate();
        }
    }
}
