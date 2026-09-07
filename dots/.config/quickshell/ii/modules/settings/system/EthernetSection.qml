import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: 6

    property var ethernetDevices: []
    property bool refreshing: ethernetProc.running
    property var autoconnectOverrides: ({})
    property string expandedDeviceName: ""

    component InfoRow: RowLayout {
        property string label
        property string value
        property bool allowCopy: false
        property bool copied: false

        Timer {
            id: copyTimer
            interval: 1500
            onTriggered: copied = false
        }

        Layout.fillWidth: true
        spacing: 8

        StyledText {
            text: label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            Layout.preferredWidth: 100
        }

        StyledText {
            Layout.fillWidth: true
            text: value || "--"
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.family: allowCopy ? Appearance.font.family.monospace : Appearance.font.family.main
            color: Appearance.colors.colOnSecondaryContainer
            elide: Text.ElideRight
        }

        RippleButton {
            visible: allowCopy && (value !== "" && value !== "--")
            implicitWidth: 24
            implicitHeight: 24
            buttonRadius: Appearance.rounding.full
            onClicked: {
                Quickshell.clipboardText = value;
                copied = true;
                copyTimer.restart();
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: copied ? "check" : "content_copy"
                iconSize: 14
                color: copied ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            StyledToolTip {
                text: copied ? Translation.tr("Copied") : Translation.tr("Copy to clipboard")
            }
        }
    }

    function refresh() {
        if (!ethernetProc.running) {
            ethernetProc.running = true;
        }
    }

    function isAutoconnectEnabled(dev) {
        if (!dev) return false;
        if (Object.prototype.hasOwnProperty.call(autoconnectOverrides, dev.device)) {
            return autoconnectOverrides[dev.device];
        }
        return dev.autoconnect ?? true;
    }

    function setAutoconnect(dev, enabled) {
        if (!dev) return;
        const overrides = Object.assign({}, autoconnectOverrides);
        overrides[dev.device] = enabled;
        autoconnectOverrides = overrides;

        const uuid = dev.conUuid;
        if (uuid && uuid.length > 0) {
            Quickshell.execDetached(["nmcli", "connection", "modify", uuid, "connection.autoconnect", enabled ? "yes" : "no"]);
        } else {
            Quickshell.execDetached(["nmcli", "connection", "modify", dev.device, "connection.autoconnect", enabled ? "yes" : "no"]);
        }
        refreshTimer.restart();
    }

    function connectDevice(dev) {
        if (!dev) return;
        if (dev.conUuid && dev.conUuid.length > 0) {
            Quickshell.execDetached(["nmcli", "connection", "up", "uuid", dev.conUuid]);
        } else {
            Quickshell.execDetached(["nmcli", "device", "connect", dev.device]);
        }
        refreshTimer.restart();
    }

    function disconnectDevice(dev) {
        if (!dev) return;
        if (dev.conUuid && dev.conUuid.length > 0) {
            Quickshell.execDetached(["nmcli", "connection", "down", "uuid", dev.conUuid]);
        } else {
            Quickshell.execDetached(["nmcli", "device", "disconnect", dev.device]);
        }
        refreshTimer.restart();
    }

    Component.onCompleted: {
        refresh();
    }

    Timer {
        id: refreshTimer
        interval: 1000
        repeat: false
        onTriggered: root.refresh()
    }

    Connections {
        target: Network
        function onEthernetChanged() {
            refreshTimer.restart();
        }
    }

    Process {
        id: ethernetProc
        command: [FileUtils.trimFileProtocol(`${Directories.scriptPath}/network/ethernet-info.sh`)]
        environment: ({
            LANG: "C",
            LC_ALL: "C"
        })
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.ethernetDevices = Array.isArray(parsed) ? parsed : [];
                    // Default expand the first connected or active device if none expanded
                    if (root.expandedDeviceName === "" && root.ethernetDevices.length > 0) {
                        const connected = root.ethernetDevices.find(d => d.state === "connected");
                        root.expandedDeviceName = connected ? connected.device : root.ethernetDevices[0].device;
                    }
                } catch (e) {
                    console.log("[EthernetSection] Failed to parse ethernet info:", e);
                }
            }
        }
    }

    // Section Header
    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        OptionalMaterialSymbol {
            icon: "settings_ethernet"
            iconSize: Appearance.font.pixelSize.hugeass
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Ethernet (RJ45)")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
            color: Appearance.colors.colOnSecondaryContainer
        }

        DialogButton {
            buttonText: root.refreshing ? Translation.tr("Refreshing…") : Translation.tr("Refresh")
            enabled: !root.refreshing
            onClicked: root.refresh()
        }
    }

    // Empty state when no ethernet interface exists
    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        visible: root.ethernetDevices.length === 0
        text: Translation.tr("No Ethernet hardware interfaces detected.")
        color: Appearance.colors.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }

    // Repeater for Ethernet devices
    Repeater {
        model: root.ethernetDevices

        delegate: Rectangle {
            id: devCard
            required property var modelData
            required property int index

            readonly property bool isConnected: modelData.state === "connected"
            readonly property bool isConnecting: modelData.state === "connecting"
            readonly property bool hasCarrier: modelData.carrier === true
            readonly property bool isExpanded: root.expandedDeviceName === modelData.device

            Layout.fillWidth: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2
            border.width: 1
            border.color: isConnected
                ? Appearance.colors.colPrimary
                : Appearance.colors.colLayer2Hover

            implicitHeight: cardContent.implicitHeight + 16

            Behavior on implicitHeight {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(devCard)
            }

            ColumnLayout {
                id: cardContent
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: 10
                }
                spacing: 10

                // Header / Clickable summary row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: headerRow.implicitHeight

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.expandedDeviceName = devCard.isExpanded ? "" : devCard.modelData.device;
                            }
                        }

                        RowLayout {
                            id: headerRow
                            anchors.fill: parent
                            spacing: 10

                            // State icon container
                            Rectangle {
                                width: 36
                                height: 36
                                radius: Appearance.rounding.small
                                color: devCard.isConnected
                                    ? Appearance.colors.colPrimary
                                    : devCard.hasCarrier
                                        ? Appearance.colors.colSecondaryContainer
                                        : Appearance.colors.colLayer1

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    iconSize: 20
                                    text: devCard.isConnected
                                        ? "settings_ethernet"
                                        : devCard.hasCarrier
                                            ? "lan"
                                            : "cable"
                                    color: devCard.isConnected
                                        ? Appearance.colors.colOnPrimary
                                        : devCard.hasCarrier
                                            ? Appearance.colors.colOnSecondaryContainer
                                            : Appearance.colors.colSubtext
                                }
                            }

                            // Device title and status text
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                RowLayout {
                                    spacing: 6
                                    StyledText {
                                        text: devCard.modelData.connection || devCard.modelData.device
                                        font.weight: Font.Medium
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnSecondaryContainer
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: devCard.modelData.device !== ""
                                        radius: Appearance.rounding.unsharpenmore
                                        color: Appearance.colors.colLayer1
                                        implicitWidth: devNameText.implicitWidth + 8
                                        implicitHeight: devNameText.implicitHeight + 2

                                        StyledText {
                                            id: devNameText
                                            anchors.centerIn: parent
                                            text: devCard.modelData.device
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.family: Appearance.font.family.monospace
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: devCard.isConnected
                                        ? Appearance.colors.colPrimary
                                        : Appearance.colors.colSubtext
                                    elide: Text.ElideRight
                                    text: {
                                        if (devCard.isConnected) {
                                            const ipStr = devCard.modelData.ipv4.length > 0 ? devCard.modelData.ipv4[0] : "";
                                            const speedStr = devCard.modelData.speed ? ` · ${devCard.modelData.speed}` : "";
                                            return ipStr ? `${Translation.tr("Connected")} · ${ipStr}${speedStr}` : Translation.tr("Connected");
                                        } else if (devCard.isConnecting) {
                                            return Translation.tr("Connecting…");
                                        } else if (devCard.hasCarrier) {
                                            return Translation.tr("Cable connected (inactive)");
                                        } else {
                                            return Translation.tr("Cable unplugged");
                                        }
                                    }
                                }
                            }

                            MaterialSymbol {
                                text: "keyboard_arrow_down"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                rotation: devCard.isExpanded ? 180 : 0
                                Behavior on rotation {
                                    NumberAnimation {
                                        duration: 150
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    // Action button
                    DialogButton {
                        visible: devCard.isConnected
                        buttonText: Translation.tr("Disconnect")
                        onClicked: root.disconnectDevice(devCard.modelData)
                    }

                    DialogButton {
                        visible: !devCard.isConnected && devCard.hasCarrier
                        buttonText: Translation.tr("Connect")
                        onClicked: root.connectDevice(devCard.modelData)
                    }
                }

                // Collapsible detailed information and settings
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: devCard.isExpanded
                    spacing: 8

                    // Divider line
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Appearance.colors.colLayer2Hover
                    }

                    // Autoconnect toggle row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MaterialSymbol {
                            text: "autorenew"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Connect automatically")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnSecondaryContainer
                        }

                        StyledSwitch {
                            checked: root.isAutoconnectEnabled(devCard.modelData)
                            onClicked: root.setAutoconnect(devCard.modelData, !root.isAutoconnectEnabled(devCard.modelData))
                        }
                    }

                    // Details box
                    Rectangle {
                        Layout.fillWidth: true
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        implicitHeight: detailsColumn.implicitHeight + 14

                        ColumnLayout {
                            id: detailsColumn
                            anchors {
                                top: parent.top
                                left: parent.left
                                right: parent.right
                                margins: 8
                            }
                            spacing: 6


                            InfoRow {
                                label: Translation.tr("Network interface")
                                value: devCard.modelData.device
                            }

                            InfoRow {
                                label: Translation.tr("Hardware MAC")
                                value: devCard.modelData.hwaddr
                                allowCopy: true
                            }

                            InfoRow {
                                label: Translation.tr("Carrier status")
                                value: devCard.hasCarrier ? Translation.tr("Cable plugged in") : Translation.tr("Cable unplugged")
                            }

                            InfoRow {
                                visible: devCard.modelData.speed !== ""
                                label: Translation.tr("Link speed")
                                value: devCard.modelData.speed
                            }

                            InfoRow {
                                visible: devCard.modelData.ipv4.length > 0
                                label: Translation.tr("IPv4 address")
                                value: devCard.modelData.ipv4.join(", ")
                                allowCopy: true
                            }

                            InfoRow {
                                visible: devCard.modelData.gateway4 !== ""
                                label: Translation.tr("IPv4 gateway")
                                value: devCard.modelData.gateway4
                                allowCopy: true
                            }

                            InfoRow {
                                visible: devCard.modelData.dns4.length > 0
                                label: Translation.tr("DNS servers")
                                value: devCard.modelData.dns4.join(", ")
                                allowCopy: true
                            }

                            InfoRow {
                                visible: devCard.modelData.ipv6.length > 0
                                label: Translation.tr("IPv6 address")
                                value: devCard.modelData.ipv6.join(", ")
                                allowCopy: true
                            }
                        }
                    }
                }
            }
        }
    }
}
