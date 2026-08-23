pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Singleton {
    id: root

    readonly property string modelName: "OnePlus Buds 3"
    readonly property int bluetoothRevision: BluetoothStatus.deviceRevision
    readonly property var device: {
        const revision = root.bluetoothRevision;
        return Bluetooth.devices.values.find(candidate => {
            if (!candidate?.connected)
                return false;
            const name = String(candidate.name ?? candidate.deviceName ?? "")
                .toLowerCase().replace(/[^a-z0-9]/g, "");
            return name === "oneplusbuds3";
        }) ?? null;
    }
    readonly property bool available: root.device !== null
    readonly property string address: root.device?.address ?? ""
    readonly property bool connecting: root.available && bridgeProcess.running && !root.connected

    property bool controlsActive: false
    property bool connected: false
    property string activeAddress: ""
    property string lastError: ""
    property int channel: -1
    property int batteryLeft: -1
    property int batteryRight: -1
    property int batteryCase: -1
    property bool chargingLeft: false
    property bool chargingRight: false
    property bool chargingCase: false
    property string ancMode: "unknown"
    property int eqPreset: -1
    property int spatial: -1
    property int gameMode: -1
    property int gameSound: -1
    property int dualDevice: -1
    property int wearDetection: -1

    function resetState() {
        root.connected = false;
        root.channel = -1;
        root.batteryLeft = -1;
        root.batteryRight = -1;
        root.batteryCase = -1;
        root.chargingLeft = false;
        root.chargingRight = false;
        root.chargingCase = false;
        root.ancMode = "unknown";
        root.eqPreset = -1;
        root.spatial = -1;
        root.gameMode = -1;
        root.gameSound = -1;
        root.dualDevice = -1;
        root.wearDetection = -1;
    }

    function bridgeCommand() {
        return FileUtils.trimFileProtocol(`${Directories.scriptPath}/bluetooth/oplus-buds3-bridge.sh`);
    }

    function syncBridge() {
        if (!root.controlsActive || !root.available || root.address.length === 0) {
            retryTimer.stop();
            if (bridgeProcess.running)
                bridgeProcess.running = false;
            root.activeAddress = "";
            root.resetState();
            return;
        }

        if (bridgeProcess.running && root.activeAddress === root.address)
            return;
        if (bridgeProcess.running) {
            bridgeProcess.running = false;
            restartTimer.restart();
            return;
        }

        root.activeAddress = root.address;
        root.lastError = "";
        bridgeProcess.command = [root.bridgeCommand(), root.address];
        bridgeProcess.running = true;
    }

    function activate() {
        if (root.controlsActive)
            return;
        root.controlsActive = true;
        root.syncBridge();
    }

    function deactivate() {
        if (!root.controlsActive)
            return;
        root.controlsActive = false;
        restartTimer.stop();
        retryTimer.stop();
        if (bridgeProcess.running)
            bridgeProcess.running = false;
        root.activeAddress = "";
        root.lastError = "";
        root.resetState();
    }

    function restart() {
        retryTimer.stop();
        root.lastError = "";
        root.resetState();
        if (bridgeProcess.running) {
            bridgeProcess.running = false;
            restartTimer.restart();
        } else {
            root.syncBridge();
        }
    }

    function send(command) {
        if (!bridgeProcess.running || !root.connected)
            return;
        bridgeProcess.write(command + "\n");
    }

    function refresh() { root.send("query"); }
    function setAnc(mode) { root.send(`anc ${mode}`); }
    function setEq(preset) { root.send(`eq ${preset}`); }
    function setSpatial(enabled) { root.send(`spatial ${enabled ? 1 : 0}`); }
    function setGameMode(enabled) { root.send(`game ${enabled ? 1 : 0}`); }
    function setGameSound(enabled) { root.send(`game_sound ${enabled ? 1 : 0}`); }
    function setDualDevice(enabled) { root.send(`dual ${enabled ? 1 : 0}`); }
    function setWearDetection(enabled) { root.send(`wear ${enabled ? 1 : 0}`); }

    function applyNullableInt(data, key, fallback) {
        return data[key] === null || data[key] === undefined ? fallback : Number(data[key]);
    }

    function handleLine(line) {
        const trimmed = String(line).trim();
        if (trimmed.length === 0)
            return;

        let data;
        try {
            data = JSON.parse(trimmed);
        } catch (error) {
            console.warn(`[OplusBuds3] Invalid bridge output: ${trimmed}`);
            return;
        }

        if (data.type === "error") {
            root.lastError = String(data.message ?? "Unknown error");
            root.connected = false;
            return;
        }
        if (data.type !== "state")
            return;

        root.connected = data.connected === true;
        root.channel = root.applyNullableInt(data, "channel", -1);
        root.batteryLeft = root.applyNullableInt(data, "batteryLeft", -1);
        root.batteryRight = root.applyNullableInt(data, "batteryRight", -1);
        root.batteryCase = root.applyNullableInt(data, "batteryCase", -1);
        root.chargingLeft = data.chargingLeft === true;
        root.chargingRight = data.chargingRight === true;
        root.chargingCase = data.chargingCase === true;
        root.ancMode = String(data.anc ?? "unknown");
        root.eqPreset = root.applyNullableInt(data, "eq", -1);
        root.spatial = data.spatial === null || data.spatial === undefined ? -1 : (data.spatial ? 1 : 0);
        root.gameMode = data.gameMode === null || data.gameMode === undefined ? -1 : (data.gameMode ? 1 : 0);
        root.gameSound = data.gameSound === null || data.gameSound === undefined ? -1 : (data.gameSound ? 1 : 0);
        root.dualDevice = data.dualDevice === null || data.dualDevice === undefined ? -1 : (data.dualDevice ? 1 : 0);
        root.wearDetection = data.wearDetection === null || data.wearDetection === undefined ? -1 : (data.wearDetection ? 1 : 0);
        if (root.connected)
            root.lastError = "";
    }

    onBluetoothRevisionChanged: {
        if (root.controlsActive)
            Qt.callLater(root.syncBridge);
    }

    Timer {
        id: restartTimer
        interval: 250
        repeat: false
        onTriggered: root.syncBridge()
    }

    Timer {
        id: retryTimer
        interval: 3000
        repeat: false
        onTriggered: root.syncBridge()
    }

    Process {
        id: bridgeProcess
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }

        stderr: SplitParser {
            onRead: line => {
                const message = String(line).trim();
                if (message.length === 0)
                    return;
                console.warn(`[OplusBuds3] ${message}`);
                root.lastError = message;
            }
        }

        onStarted: root.lastError = ""
        onExited: (exitCode, exitStatus) => {
            root.connected = false;
            if (root.available && root.activeAddress === root.address)
                retryTimer.restart();
        }
    }
}
