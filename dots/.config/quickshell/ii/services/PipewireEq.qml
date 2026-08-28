pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Manages per-device PipeWire filter graphs.
 */
Singleton {
    id: root

    readonly property string managerPath: FileUtils.trimFileProtocol(`${Directories.scriptPath}/audio/pipewire-eq.py`)
    readonly property bool busy: managerProcess.running
    readonly property bool hasEnabledProfiles: devices.some(device => device.enabled)
    property bool available: false
    property list<var> devices: []
    property string configPath: ""
    property string dataPath: ""
    property string lastMessage: ""
    property string lastError: ""
    property bool reconcilePending: false

    signal operationFinished(bool success, string message)

    function profileFor(deviceName) {
        return root.devices.find(device => device.device === deviceName) ?? null;
    }

    function run(arguments, operation = "") {
        if (managerProcess.running) {
            root.lastError = Translation.tr("Another EQ operation is still running.");
            root.operationFinished(false, root.lastError);
            return false;
        }
        root.lastError = "";
        root.lastMessage = "";
        managerProcess.operation = operation;
        managerProcess.responseReceived = false;
        managerProcess.command = [root.managerPath, ...arguments];
        managerProcess.running = true;
        return true;
    }

    function refresh() {
        root.run(["status"], "status");
    }

    function reconcile() {
        if (managerProcess.running) {
            root.reconcilePending = true;
            return;
        }
        root.run(["reconcile"], "reconcile");
    }

    function importProfile(deviceName, description, channels, filePath) {
        root.run([
            "import",
            "--device", deviceName,
            "--description", description,
            "--channels", String(channels),
            "--file", FileUtils.trimFileProtocol(filePath),
        ], "import");
    }

    function setEnabled(deviceName, enabled) {
        root.run([enabled ? "enable" : "disable", "--device", deviceName], enabled ? "enable" : "disable");
    }

    function forget(deviceName) {
        root.run(["forget", "--device", deviceName], "forget");
    }

    function apply() {
        root.run(["apply"], "apply");
    }

    Component.onCompleted: reconcileTimer.start()

    Connections {
        target: Audio

        function onOutputDevicesChanged() {
            root.reconcilePending = true;
            reconcileTimer.restart();
        }
    }

    Timer {
        id: reconcileTimer
        interval: 500
        repeat: false
        onTriggered: {
            root.reconcilePending = false;
            root.reconcile();
        }
    }

    function applyResponse(text) {
        try {
            const response = JSON.parse(text.trim());
            managerProcess.responseReceived = true;
            if (!response.ok) {
                root.lastError = response.error ?? Translation.tr("The EQ operation failed.");
                root.operationFinished(false, root.lastError);
                return;
            }
            if (response.available !== undefined)
                root.available = response.available;
            if (response.devices !== undefined)
                root.devices = response.devices;
            root.configPath = response.configPath ?? root.configPath;
            root.dataPath = response.dataPath ?? root.dataPath;
            root.lastMessage = response.message ?? "";
            root.operationFinished(true, root.lastMessage);
        } catch (error) {
            managerProcess.responseReceived = true;
            root.lastError = Translation.tr("Could not parse the EQ manager response.");
            root.operationFinished(false, root.lastError);
        }
    }

    Process {
        id: managerProcess
        property string operation: ""
        property bool responseReceived: false

        stdout: StdioCollector {
            onStreamFinished: root.applyResponse(text)
        }
        onExited: (exitCode, exitStatus) => {
            if (!managerProcess.responseReceived) {
                root.lastError = Translation.tr("The EQ manager exited without a response.");
                root.operationFinished(false, root.lastError);
            }
            if (root.reconcilePending)
                reconcileTimer.restart();
        }
    }
}
