pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import QtQuick
import QtQml.Models
import qs.modules.common
import qs.services

Singleton {
    id: root

    // BlueZ often adds Battery1 after Connected=true. JS .filter/.some on
    // Bluetooth.devices.values does not re-run when a device property changes,
    // so bump this from per-device Connections. UPower HID batteries (Pro
    // Controller, mice) use the same revision.
    property int deviceRevision: 0

    readonly property bool available: Bluetooth.adapters.values.length > 0
    readonly property bool enabled: Bluetooth.defaultAdapter?.enabled ?? false

    property list<var> connectedDevices: []
    property list<var> pairedButNotConnectedDevices: []
    property list<var> unpairedDevices: []
    property list<var> friendlyDeviceList: []
    property list<var> namedDeviceList: []
    property list<var> unnamedDeviceList: []

    readonly property BluetoothDevice firstActiveDevice: connectedDevices.length > 0 ? connectedDevices[0] : null
    readonly property int activeDeviceCount: connectedDevices.length
    readonly property bool connected: activeDeviceCount > 0
    readonly property var connectedBatteryDevices: {
        var _ = root.deviceRevision;
        return connectedDevices.filter(d => root.batteryFraction(d) >= 0);
    }
    readonly property bool hasConnectedBattery: connectedBatteryDevices.length > 0

    onAvailableChanged: scheduleUpdate(true)
    onEnabledChanged: scheduleUpdate(true)

    Connections {
        target: Bluetooth
        function onDefaultAdapterChanged() {
            root.scheduleUpdate(true);
        }
    }

    readonly property var macRegex: /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/

    function isMacName(name) {
        return root.macRegex.test(name ?? "");
    }

    function sortFunction(a, b) {
        if (!a || !b) return 0;
        const nameA = a.name || "";
        const nameB = b.name || "";
        const aIsMacOrEmpty = !nameA || root.isMacName(nameA);
        const bIsMacOrEmpty = !nameB || root.isMacName(nameB);
        if (aIsMacOrEmpty !== bIsMacOrEmpty)
            return aIsMacOrEmpty ? 1 : -1;

        // Alphabetical by name
        return nameA.localeCompare(nameB);
    }

    function refresh() {
        root.deviceRevision++;
    }

    property string expandedAddress: ""
    onExpandedAddressChanged: {
        if (expandedAddress === "" && pendingUpdate) {
            pendingUpdate = false;
            updateFriendlyDeviceList();
        }
    }

    function areDeviceListsEqual(a, b) {
        if (a === b) return true;
        if (!a || !b || a.length !== b.length) return false;
        for (let i = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false;
        }
        return true;
    }

    property bool pendingUpdate: false

    Timer {
        id: updateThrottleTimer
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.expandedAddress !== "") {
                root.pendingUpdate = true;
                updateThrottleTimer.start();
                return;
            }
            root.updateFriendlyDeviceList();
            if (root.pendingUpdate) {
                root.pendingUpdate = false;
                updateThrottleTimer.start();
            }
        }
    }

    function scheduleUpdate(immediate = false) {
        if (immediate) {
            updateThrottleTimer.stop();
            pendingUpdate = false;
            root.updateFriendlyDeviceList();
            return;
        }
        if (updateThrottleTimer.running) {
            pendingUpdate = true;
        } else {
            updateThrottleTimer.start();
        }
    }

    Connections {
        target: Bluetooth.devices
        function onValuesChanged() {
            root.scheduleUpdate(false);
        }
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

    function earbudBatteryInfo(device) {
        var _ = root.deviceRevision;
        if (!device)
            return null;

        const devAddr = (device.address ?? "").toUpperCase();

        // 1. OnePlus Buds 3 provider
        if (OplusBuds3.available && OplusBuds3.connected) {
            const oplusAddr = (OplusBuds3.address ?? "").toUpperCase();
            if (devAddr.length > 0 && devAddr === oplusAddr) {
                const l = OplusBuds3.batteryLeft;
                const r = OplusBuds3.batteryRight;
                const c = OplusBuds3.batteryCase;
                const validLevels = [];
                if (l >= 0) validLevels.push(l);
                if (r >= 0) validLevels.push(r);
                const lowest = validLevels.length > 0 ? Math.min(...validLevels) : -1;
                return {
                    isEarbuds: true,
                    left: l,
                    right: r,
                    case: c,
                    lowest: lowest,
                    lowestFraction: lowest >= 0 ? (lowest / 100.0) : -1,
                    chargingLeft: OplusBuds3.chargingLeft,
                    chargingRight: OplusBuds3.chargingRight,
                    chargingCase: OplusBuds3.chargingCase
                };
            }
        }

        return null;
    }

    // 0–1 from Earbuds (lowest), BlueZ Battery1, else UPower HID; -1 if neither reports.
    function batteryFraction(device) {
        var _ = root.deviceRevision;
        if (!device)
            return -1;

        const preferLowest = Config.options?.bar?.indicators?.bluetoothBatteryLowestEarbud ?? true;
        const earbudInfo = root.earbudBatteryInfo(device);
        if (earbudInfo && earbudInfo.lowest >= 0 && preferLowest) {
            return earbudInfo.lowestFraction;
        }

        if (device.batteryAvailable)
            return device.battery;
        const u = root.uPowerBatteryFor(device);
        return u ? u.percentage : -1;
    }

    Connections {
        target: OplusBuds3
        function onBatteryLeftChanged() { root.refresh(); }
        function onBatteryRightChanged() { root.refresh(); }
        function onBatteryCaseChanged() { root.refresh(); }
        function onChargingLeftChanged() { root.refresh(); }
        function onChargingRightChanged() { root.refresh(); }
        function onChargingCaseChanged() { root.refresh(); }
        function onConnectedChanged() { root.refresh(); }
    }

    Instantiator {
        model: Bluetooth.devices
        Connections {
            required property BluetoothDevice modelData
            target: modelData
            function onConnectedChanged() {
                root.refresh();
                root.scheduleUpdate(true);
            }
            function onPairedChanged() {
                root.refresh();
                root.scheduleUpdate(true);
            }
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

    function updateFriendlyDeviceList() {
        if (!available || !enabled) {
            if (connectedDevices.length > 0) connectedDevices = [];
            if (pairedButNotConnectedDevices.length > 0) pairedButNotConnectedDevices = [];
            if (unpairedDevices.length > 0) unpairedDevices = [];
            if (friendlyDeviceList.length > 0) friendlyDeviceList = [];
            if (namedDeviceList.length > 0) namedDeviceList = [];
            if (unnamedDeviceList.length > 0) unnamedDeviceList = [];
            return;
        }
        const devices = Bluetooth.devices.values;
        const connected = devices.filter(d => d && d.connected).sort(sortFunction);
        const paired = devices.filter(d => d && d.paired && !d.connected).sort(sortFunction);
        const unpaired = devices.filter(d => d && !d.paired && !d.connected).sort(sortFunction);
        const friendly = [...connected, ...paired, ...unpaired];
        const named = friendly.filter(d => !root.isMacName(d.name));
        const unnamed = friendly.filter(d => root.isMacName(d.name));

        if (!areDeviceListsEqual(connectedDevices, connected))
            connectedDevices = connected;
        if (!areDeviceListsEqual(pairedButNotConnectedDevices, paired))
            pairedButNotConnectedDevices = paired;
        if (!areDeviceListsEqual(unpairedDevices, unpaired))
            unpairedDevices = unpaired;
        if (!areDeviceListsEqual(friendlyDeviceList, friendly))
            friendlyDeviceList = friendly;
        if (!areDeviceListsEqual(namedDeviceList, named))
            namedDeviceList = named;
        if (!areDeviceListsEqual(unnamedDeviceList, unnamed))
            unnamedDeviceList = unnamed;
    }

    Component.onCompleted: {
        updateFriendlyDeviceList();
    }
}
