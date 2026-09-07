pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    property bool isServer: (Quickshell.env("QS_CLIENT") ?? "") !== "1"
    readonly property string modelName: "OnePlus Buds 3"
    readonly property string stateFilePath: FileUtils.trimFileProtocol(`${StandardPaths.standardLocations(StandardPaths.RuntimeLocation)[0]}/quickshell-oplus-buds3.json`)

    readonly property var device: {
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
    readonly property bool connecting: root.isServer ? (root.available && bridgeProcess.running && !root.connected) : (root.available && !root.connected)

    readonly property bool shouldBeActive: root.isServer && root.available && root.address.length > 0 && (root.controlsActive || (Config.options?.bar?.indicators?.showBluetoothBattery ?? true))

    readonly property int lowestBattery: {
        if (!root.connected) return -1;
        const l = root.batteryLeft;
        const r = root.batteryRight;
        if (l >= 0 && r >= 0) return Math.min(l, r);
        if (l >= 0) return l;
        if (r >= 0) return r;
        return -1;
    }
    readonly property bool hasEarbudBattery: lowestBattery >= 0

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
    property int hiRes: -1

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
        root.hiRes = -1;
        if (root.isServer)
            root.saveStateToFile();
    }

    function bridgeCommand() {
        return FileUtils.trimFileProtocol(`${Directories.scriptPath}/bluetooth/oplus-buds3-bridge.sh`);
    }

    function saveStateToFile() {
        if (!root.isServer)
            return;
        const obj = {
            type: "state",
            connected: root.connected,
            address: root.activeAddress || root.address,
            channel: root.channel,
            batteryLeft: root.batteryLeft,
            batteryRight: root.batteryRight,
            batteryCase: root.batteryCase,
            chargingLeft: root.chargingLeft,
            chargingRight: root.chargingRight,
            chargingCase: root.chargingCase,
            anc: root.ancMode,
            eq: root.eqPreset,
            spatial: root.spatial,
            gameMode: root.gameMode,
            gameSound: root.gameSound,
            dualDevice: root.dualDevice,
            wearDetection: root.wearDetection,
            hiRes: root.hiRes,
            lastError: root.lastError
        };
        stateFileView.setText(JSON.stringify(obj) + "\n");
    }

    function syncBridge() {
        if (!root.isServer)
            return;

        if (!root.shouldBeActive || root.address.length === 0) {
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

    function callServer(method, arg = "") {
        const cmd = ["qs", "-c", "ii", "ipc", "call", "oplusBuds3", method];
        if (arg !== "" && arg !== undefined && arg !== null)
            cmd.push(String(arg));
        Quickshell.execDetached(cmd);
    }

    function activate() {
        if (root.controlsActive)
            return;
        root.controlsActive = true;
        if (!root.isServer) {
            stateFileView.reload();
            root.refresh();
        } else {
            root.syncBridge();
        }
    }

    function deactivate() {
        if (!root.controlsActive)
            return;
        root.controlsActive = false;
        if (root.isServer) {
            root.syncBridge();
        }
    }

    function restart() {
        if (!root.isServer) {
            root.callServer("restart");
            return;
        }
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
        if (!root.isServer || !bridgeProcess.running || !root.connected)
            return;
        bridgeProcess.write(command + "\n");
    }

    function refresh() {
        if (root.isServer) root.send("query");
        else root.callServer("refresh");
    }
    function setAnc(mode) {
        if (root.isServer) root.send(`anc ${mode}`);
        else root.callServer("setAnc", mode);
    }
    function setEq(preset) {
        if (root.isServer) root.send(`eq ${preset}`);
        else root.callServer("setEq", preset);
    }
    function setSpatial(enabled) {
        const val = enabled ? 1 : 0;
        if (root.isServer) root.send(`spatial ${val}`);
        else root.callServer("setSpatial", val);
    }
    function setGameMode(enabled) {
        const val = enabled ? 1 : 0;
        if (root.isServer) root.send(`game ${val}`);
        else root.callServer("setGameMode", val);
    }
    function setGameSound(enabled) {
        const val = enabled ? 1 : 0;
        if (root.isServer) root.send(`game_sound ${val}`);
        else root.callServer("setGameSound", val);
    }
    function setDualDevice(enabled) {
        const val = enabled ? 1 : 0;
        if (root.isServer) root.send(`dual ${val}`);
        else root.callServer("setDualDevice", val);
    }
    function setWearDetection(enabled) {
        const val = enabled ? 1 : 0;
        if (root.isServer) root.send(`wear ${val}`);
        else root.callServer("setWearDetection", val);
    }
    function setHiRes(enabled) {
        const val = enabled ? 1 : 0;
        if (root.isServer) root.send(`hires ${val}`);
        else root.callServer("setHiRes", val);
    }

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
            if (root.isServer)
                root.saveStateToFile();
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
        root.hiRes = data.hiRes === null || data.hiRes === undefined ? -1 : (data.hiRes ? 1 : 0);
        if (root.connected)
            root.lastError = "";

        if (root.isServer)
            root.saveStateToFile();
    }

    onShouldBeActiveChanged: {
        if (root.isServer)
            Qt.callLater(root.syncBridge);
    }

    Connections {
        target: Bluetooth.devices
        function onValuesChanged() {
            if (root.isServer)
                Qt.callLater(root.syncBridge);
        }
    }

    Component.onCompleted: {
        if (root.isServer) {
            root.saveStateToFile();
            if (root.shouldBeActive)
                Qt.callLater(root.syncBridge);
        } else {
            stateFileView.reload();
        }
    }

    FileView {
        id: stateFileView
        path: Qt.resolvedUrl(root.stateFilePath)
        onLoaded: {
            if (!root.isServer) {
                const content = stateFileView.text();
                if (content && content.length > 0)
                    root.handleLine(content);
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound && root.isServer) {
                root.saveStateToFile();
            }
        }
    }

    IpcHandler {
        target: "oplusBuds3"

        function setAnc(mode: string): void { root.setAnc(mode); }
        function setEq(preset: string): void { root.setEq(Number(preset)); }
        function setSpatial(enabled: string): void { root.setSpatial(enabled === "1" || enabled === "true"); }
        function setGameMode(enabled: string): void { root.setGameMode(enabled === "1" || enabled === "true"); }
        function setGameSound(enabled: string): void { root.setGameSound(enabled === "1" || enabled === "true"); }
        function setDualDevice(enabled: string): void { root.setDualDevice(enabled === "1" || enabled === "true"); }
        function setWearDetection(enabled: string): void { root.setWearDetection(enabled === "1" || enabled === "true"); }
        function setHiRes(enabled: string): void { root.setHiRes(enabled === "1" || enabled === "true"); }
        function refresh(): void { root.refresh(); }
        function restart(): void { root.restart(); }
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

    Timer {
        id: clientPollTimer
        interval: 1500
        repeat: true
        running: !root.isServer && root.controlsActive
        onTriggered: stateFileView.reload()
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
            if (root.isServer)
                root.saveStateToFile();
            if (root.isServer && root.shouldBeActive && root.activeAddress === root.address)
                retryTimer.restart();
        }
    }
}

