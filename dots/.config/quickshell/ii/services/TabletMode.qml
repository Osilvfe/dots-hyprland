pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    property bool isTabletMode: false
    property bool autoDetect: true

    readonly property string stateFilePath: `${StandardPaths.standardLocations(StandardPaths.RuntimeLocation)[0]}/hypr_tablet_mode`

    FileView {
        id: stateFile
        path: FileUtils.trimFileProtocol(root.stateFilePath)
        onLoaded: {
            const val = stateFile.text().trim();
            root.isTabletMode = (val === "1" || val === "true");
        }
    }

    FileWatch {
        path: FileUtils.trimFileProtocol(root.stateFilePath)
        onFileChanged: {
            stateFile.reload();
        }
    }

    function check(): void {
        const script = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/tablet_mode.sh`;
        Quickshell.execDetached(["bash", script, "check"]);
    }

    function toggle(): void {
        const script = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/tablet_mode.sh`;
        Quickshell.execDetached(["bash", script, "toggle"]);
    }

    IpcHandler {
        target: "tabletMode"

        function set(val: bool): void {
            root.isTabletMode = val;
        }

        function toggle(): void {
            root.toggle();
        }

        function check(): void {
            root.check();
        }
    }

    Component.onCompleted: {
        const script = `${FileUtils.trimFileProtocol(Directories.config)}/hypr/hyprland/scripts/tablet_mode.sh`;
        // Start background hardware listener on shell boot
        Quickshell.execDetached(["bash", script, "listen"]);
    }
}
