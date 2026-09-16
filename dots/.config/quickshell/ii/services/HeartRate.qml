pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services

Singleton {
    id: root

    readonly property bool isServer: (Quickshell.env("QS_CLIENT") ?? "") !== "1"
    readonly property string stateFilePath: FileUtils.trimFileProtocol(`${StandardPaths.standardLocations(StandardPaths.RuntimeLocation)[0]}/quickshell-heart-rate.json`)

    property bool connected: false
    property string source: "none"
    property string deviceName: ""
    property string deviceAddress: ""
    property string sensorLocation: ""
    property int bpm: 0
    property int lastUpdate: 0
    property int zone: 0
    property string zoneName: "No Data"
    property color zoneColor: "#64748b"
    property int battery: -1
    property var rrIntervals: []
    property bool isMock: false

    property int minBpm: 0
    property int maxBpm: 0
    property real avgBpm: 0.0
    property int duration: 0
    property int totalSamples: 0
    property var history: []
    property var discoveredDevices: []

    readonly property bool active: (root.connected || root.bpm > 0 || root.isMock) && (Config.options?.heartRate?.enable ?? true)

    function init() {
        // Calling init ensures singleton instantiation
    }

    function bridgeCommand() {
        return FileUtils.trimFileProtocol(`${Directories.scriptPath}/bluetooth/heart-rate-bridge.sh`);
    }

    function send(command: string) {
        if (root.isServer) {
            if (bridgeProcess.running) {
                bridgeProcess.write(command + "\n");
            }
        } else {
            // Forward command via IPC
            const args = command.trim().split(" ");
            const action = args[0];
            const param = args.slice(1).join(" ");
            if (action === "mock") {
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "setMock", param === "on" ? "1" : "0"]);
            } else if (action === "connect") {
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "connect", param]);
            } else if (action === "disconnect") {
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "disconnect"]);
            } else if (action === "scan") {
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "scan"]);
            } else if (action === "reset_stats") {
                Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "resetStats"]);
            }
        }
    }

    function toggleMock() {
        if (root.isServer) {
            root.send(root.isMock ? "mock off" : "mock on");
        } else {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "toggleMock"]);
        }
    }

    function setMock(enable: bool) {
        if (root.isServer) {
            root.send(enable ? "mock on" : "mock off");
        } else {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "setMock", enable ? "1" : "0"]);
        }
    }

    function connectDevice(address: string) {
        if (root.isServer) {
            root.send(`connect ${address}`);
        } else {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "connect", address]);
        }
    }

    function disconnectDevice() {
        if (root.isServer) {
            root.send("disconnect");
        } else {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "disconnect"]);
        }
    }

    function scanDevices() {
        if (root.isServer) {
            root.send("scan");
        } else {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "scan"]);
        }
    }

    function resetStats() {
        if (root.isServer) {
            root.send("reset_stats");
        } else {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "heartRate", "resetStats"]);
        }
    }

    function handleLine(line) {
        const trimmed = String(line).trim();
        if (trimmed.length === 0 || trimmed.startsWith("["))
            return;

        let data;
        try {
            data = JSON.parse(trimmed);
        } catch (e) {
            return;
        }

        if (data.type !== "heart_rate")
            return;

        root.connected = data.connected === true;
        root.source = String(data.source ?? "none");
        root.deviceName = String(data.device_name ?? "");
        root.deviceAddress = String(data.device_address ?? "");
        root.sensorLocation = String(data.sensor_location ?? "");
        root.bpm = Number(data.bpm ?? 0);
        root.lastUpdate = Number(data.last_update ?? 0);
        root.zone = Number(data.zone ?? 0);
        root.zoneName = String(data.zone_name ?? "No Data");
        root.zoneColor = String(data.zone_color ?? "#64748b");
        root.battery = Number(data.battery ?? -1);
        root.rrIntervals = Array.isArray(data.rr_intervals) ? data.rr_intervals : [];
        root.isMock = data.is_mock === true;

        if (data.stats) {
            root.minBpm = Number(data.stats.min ?? 0);
            root.maxBpm = Number(data.stats.max ?? 0);
            root.avgBpm = Number(data.stats.avg ?? 0.0);
            root.duration = Number(data.stats.duration ?? 0);
            root.totalSamples = Number(data.stats.total_samples ?? 0);
            root.history = Array.isArray(data.stats.history) ? data.stats.history : [];
        }

        if (Array.isArray(data.discovered_devices)) {
            root.discoveredDevices = data.discovered_devices;
        }
    }

    Component.onCompleted: {
        if (!root.isServer) {
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
    }

    Timer {
        id: clientPollTimer
        interval: 1000
        repeat: true
        running: !root.isServer
        onTriggered: stateFileView.reload()
    }

    IpcHandler {
        target: "heartRate"

        function toggleMock(): void { root.toggleMock(); }
        function setMock(enable: string): void { root.setMock(enable === "1" || enable === "true"); }
        function connect(address: string): void { root.connectDevice(address); }
        function disconnect(): void { root.disconnectDevice(); }
        function scan(): void { root.scanDevices(); }
        function resetStats(): void { root.resetStats(); }
    }

    Process {
        id: bridgeProcess
        stdinEnabled: true
        running: root.isServer && (Config.options?.heartRate?.enable ?? true)

        command: {
            const cmd = [
                root.bridgeCommand(),
                "--udp-port", String(Config.options?.heartRate?.udpPort ?? 9000),
                "--max-hr", String(Config.options?.heartRate?.maxHr ?? 190),
                "--resting-hr", String(Config.options?.heartRate?.restingHr ?? 60)
            ];
            const pref = String(Config.options?.heartRate?.preferredDevice ?? "").trim();
            if (pref.length > 0) {
                cmd.push("--preferred-device", pref);
            }
            if (!(Config.options?.heartRate?.autoConnect ?? true)) {
                cmd.push("--no-auto-connect");
            }
            if (Config.options?.heartRate?.mock ?? false) {
                cmd.push("--mock");
            }
            return cmd;
        }

        stdout: SplitParser {
            onRead: line => root.handleLine(line)
        }

        stderr: SplitParser {
            onRead: line => {
                const message = String(line).trim();
                if (message.length === 0)
                    return;
                console.warn(`[HeartRateBridge] ${message}`);
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.connected = false;
            if (root.isServer && (Config.options?.heartRate?.enable ?? true)) {
                retryTimer.restart();
            }
        }
    }

    Timer {
        id: retryTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.isServer && !bridgeProcess.running && (Config.options?.heartRate?.enable ?? true)) {
                bridgeProcess.running = true;
            }
        }
    }
}
