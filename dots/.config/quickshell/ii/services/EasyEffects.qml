import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
pragma Singleton
pragma ComponentBehavior: Bound

/**
 * Handles JamesDSP active state and presets.
 */
Singleton {
    id: root

    property bool available: false
    property bool active: false

    function fetchAvailability() {
        fetchAvailabilityProc.running = true
    }

    function fetchActiveState() {
        fetchActiveStateProc.running = true
    }

    function disable() {
        root.active = false
        Quickshell.execDetached(["bash", "-c", "pkill jamesdsp || pkill -f jamesdsp"])
    }

    function enable() {
        root.active = true
        Quickshell.execDetached(["bash", "-c", "jamesdsp -t"])
    }

    function toggle() {
        if (root.active) {
            root.disable()
        } else {
            root.enable()
        }
    }

    Process {
        id: fetchAvailabilityProc
        running: true
        command: ["bash", "-c", "command -v jamesdsp > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0
        }
    }

    Process {
        id: fetchActiveStateProc
        running: true
        command: ["bash", "-c", "pidof jamesdsp > /dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.active = exitCode === 0
        }
    }
}
