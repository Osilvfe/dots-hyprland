pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import QtQuick
import QtQml.Models

Singleton {
    id: root

    // BlueZ often adds Battery1 after Connected=true. JS .filter/.some on
    // Bluetooth.devices.values does not re-run when a device property changes,
    // so bump this from per-device Connections.
    property int deviceRevision: 0

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: {
        var _ = root.deviceRevision;
        return Bluetooth.devices.values.find(device => device.connected) ?? null;
    }
    readonly property int activeDeviceCount: connectedDevices.length
    readonly property bool connected: connectedDevices.length > 0
    readonly property var connectedBatteryDevices: connectedDevices.filter(d => d.batteryAvailable)
    readonly property bool hasConnectedBattery: connectedBatteryDevices.length > 0

    function isMacName(name) {
        return /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(name ?? "");
    }
    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses
        const aIsMac = root.isMacName(a.name);
        const bIsMac = root.isMacName(b.name);
        if (aIsMac !== bIsMac)
            return aIsMac ? 1 : -1;

        // Alphabetical by name
        return a.name.localeCompare(b.name);
    }

    function refresh() {
        root.deviceRevision++;
    }

    Instantiator {
        model: Bluetooth.devices
        Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() { root.refresh(); }
            function onPairedChanged() { root.refresh(); }
            function onBatteryAvailableChanged() { root.refresh(); }
            function onBatteryChanged() { root.refresh(); }
            Component.onCompleted: root.refresh()
            Component.onDestruction: root.refresh()
        }
    }

    property list<var> connectedDevices: {
        var _ = root.deviceRevision;
        return Bluetooth.devices.values.filter(d => d.connected).sort(sortFunction);
    }
    property list<var> pairedButNotConnectedDevices: {
        var _ = root.deviceRevision;
        return Bluetooth.devices.values.filter(d => d.paired && !d.connected).sort(sortFunction);
    }
    property list<var> unpairedDevices: {
        var _ = root.deviceRevision;
        return Bluetooth.devices.values.filter(d => !d.paired && !d.connected).sort(sortFunction);
    }
    property list<var> friendlyDeviceList: [
        ...connectedDevices,
        ...pairedButNotConnectedDevices,
        ...unpairedDevices
    ]
    property list<var> namedDeviceList: friendlyDeviceList.filter(d => !root.isMacName(d.name))
    property list<var> unnamedDeviceList: friendlyDeviceList.filter(d => root.isMacName(d.name))
}
