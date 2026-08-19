pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick
import QtQml.Models

Singleton {
    id: root

    // BlueZ often adds Battery1 after Connected=true. JS .filter/.some on
    // Bluetooth.devices.values does not re-run when a device property changes,
    // so bump this from per-device Connections. UPower HID batteries (Pro
    // Controller, mice) use the same revision.
    property int deviceRevision: 0

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false
    readonly property BluetoothDevice firstActiveDevice: {
        var _ = root.deviceRevision;
        return Bluetooth.devices.values.find(device => device.connected) ?? null;
    }
    readonly property int activeDeviceCount: connectedDevices.length
    readonly property bool connected: connectedDevices.length > 0
    readonly property var connectedBatteryDevices: {
        var _ = root.deviceRevision;
        return connectedDevices.filter(d => root.batteryFraction(d) >= 0);
    }
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

    function isPeripheralBattery(u) {
        if (!u?.ready || u.isLaptopBattery)
            return false;
        if (u.type === UPowerDeviceType.LinePower)
            return false;
        if (u.type === UPowerDeviceType.Battery && u.powerSupply)
            return false;
        return true;
    }

    function uPowerMatchesDevice(u, device) {
        const addr = (device?.address ?? "").toUpperCase();
        const native = (u?.nativePath ?? "").toUpperCase();
        if (addr.length > 0 && native.indexOf(addr.replace(/:/g, "_")) !== -1)
            return true;
        const model = (u?.model ?? "").toLowerCase();
        if (!model)
            return false;
        return model === (device?.name ?? "").toLowerCase()
            || model === (device?.deviceName ?? "").toLowerCase();
    }

    function uPowerBatteryFor(device) {
        var _ = root.deviceRevision;
        if (!device)
            return null;
        const list = UPower.devices.values;
        for (let i = 0; i < list.length; ++i) {
            const u = list[i];
            if (root.isPeripheralBattery(u) && root.uPowerMatchesDevice(u, device))
                return u;
        }
        return null;
    }

    // 0–1 from BlueZ Battery1, else UPower HID; -1 if neither reports.
    function batteryFraction(device) {
        var _ = root.deviceRevision;
        if (!device)
            return -1;
        if (device.batteryAvailable)
            return device.battery;
        const u = root.uPowerBatteryFor(device);
        return u ? u.percentage : -1;
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

    Instantiator {
        model: UPower.devices
        Connections {
            required property var modelData
            target: modelData
            function onPercentageChanged() { root.refresh(); }
            function onModelChanged() { root.refresh(); }
            function onNativePathChanged() { root.refresh(); }
            function onReadyChanged() { root.refresh(); }
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
