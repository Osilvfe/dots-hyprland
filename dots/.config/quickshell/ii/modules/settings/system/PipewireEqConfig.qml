import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    property string selectedDeviceName: ""
    readonly property var physicalDevices: Audio.outputDevices.filter(node => {
        const name = root.deviceName(node);
        return name.startsWith("alsa_output.") || name.startsWith("bluez_output.");
    })
    readonly property var deviceChoices: physicalDevices.map(node => ({
        displayName: Audio.friendlyDeviceName(node),
        value: root.deviceName(node),
    }))
    readonly property var selectedDevice: physicalDevices.find(node => root.deviceName(node) === selectedDeviceName) ?? null
    readonly property var selectedProfile: PipewireEq.profileFor(selectedDeviceName)

    function deviceName(node) {
        return node?.name ?? node?.properties?.["node.name"] ?? "";
    }

    function deviceChannels(node) {
        const value = Number(node?.properties?.["audio.channels"] ?? 2);
        return Number.isInteger(value) && value >= 1 && value <= 8 ? value : 2;
    }

    function ensureSelection() {
        if (root.physicalDevices.length === 0) {
            root.selectedDeviceName = "";
            return;
        }
        if (!root.physicalDevices.some(node => root.deviceName(node) === root.selectedDeviceName))
            root.selectedDeviceName = root.deviceName(root.physicalDevices[0]);
    }

    function profileSummary(profile) {
        if (!profile)
            return Translation.tr("No profile imported for this device.");
        if (profile.kind === "fir")
            return Translation.tr("%1-point FIR · 44.1/48/96/192 kHz").arg(profile.points ?? 0);
        return Translation.tr("%1-filter parametric EQ · Preamp %2 dB").arg(profile.filters ?? 0).arg(profile.preamp ?? 0);
    }

    Component.onCompleted: {
        root.ensureSelection();
        PipewireEq.refresh();
    }

    Connections {
        target: Audio
        function onOutputDevicesChanged() {
            root.ensureSelection();
        }
    }

    FileDialog {
        id: autoEqFileDialog
        title: Translation.tr("Import AutoEQ profile")
        currentFolder: Directories.music
        nameFilters: [
            Translation.tr("AutoEQ profiles (*.txt *.csv *.tsv)"),
            Translation.tr("All files (*)"),
        ]
        onAccepted: {
            if (!root.selectedDevice)
                return;
            PipewireEq.importProfile(
                root.selectedDeviceName,
                Audio.friendlyDeviceName(root.selectedDevice),
                root.deviceChannels(root.selectedDevice),
                selectedFile.toString()
            );
        }
    }

    ContentSection {
        icon: "graphic_eq"
        title: Translation.tr("Device-specific PipeWire EQ")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Attach a native PipeWire filter to each physical output device. Device names and normal audio routing stay unchanged.")
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        ConfigRow {
            StyledText {
                text: Translation.tr("Output device")
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledComboBox {
                Layout.fillWidth: true
                enabled: root.deviceChoices.length > 0 && !PipewireEq.busy
                textRole: "displayName"
                model: root.deviceChoices
                currentIndex: Math.max(0, root.deviceChoices.findIndex(choice => choice.value === root.selectedDeviceName))
                onActivated: index => root.selectedDeviceName = model[index]?.value ?? ""
            }

            DialogButton {
                buttonText: Translation.tr("Refresh")
                enabled: !PipewireEq.busy
                onClicked: {
                    root.ensureSelection();
                    PipewireEq.refresh();
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.physicalDevices.length === 0
            text: Translation.tr("No physical output device is currently available.")
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        icon: "upload_file"
        title: Translation.tr("AutoEQ profile")

        ConfigRow {
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.selectedProfile?.profileName ?? Translation.tr("Not imported")
                    color: Appearance.colors.colOnSecondaryContainer
                    elide: Text.ElideMiddle
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.profileSummary(root.selectedProfile)
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    wrapMode: Text.Wrap
                }
            }

            DialogButton {
                buttonText: Translation.tr("Import")
                enabled: root.selectedDevice !== null && !PipewireEq.busy
                onClicked: autoEqFileDialog.open()
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Frequency/gain curves are converted to minimum-phase FIR files at 44.1, 48, 96 and 192 kHz. AutoEQ ParametricEQ.txt files are loaded as native parametric filters with their Preamp value.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallie
            wrapMode: Text.Wrap
        }

        ConfigRow {
            visible: root.selectedProfile !== null

            DialogButton {
                buttonText: root.selectedProfile?.enabled ? Translation.tr("Disable for this device") : Translation.tr("Enable for this device")
                enabled: !PipewireEq.busy
                onClicked: PipewireEq.setEnabled(root.selectedDeviceName, !root.selectedProfile.enabled)
            }

            DialogButton {
                buttonText: Translation.tr("Remove")
                enabled: !PipewireEq.busy
                colText: Appearance.colors.colError
                onClicked: PipewireEq.forget(root.selectedDeviceName)
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.selectedProfile !== null
            text: root.selectedProfile?.runtimeError
                ? root.selectedProfile.runtimeError
                : !root.selectedProfile?.runtimeConnected
                    ? Translation.tr("The device is offline; the saved state will be applied when it reconnects.")
                    : root.selectedProfile?.runtimeActive
                        ? Translation.tr("EQ is active on the live device node.")
                        : root.selectedProfile?.enabled
                            ? Translation.tr("The desired EQ is enabled but is not active on the live node.")
                            : Translation.tr("EQ is bypassed on the live device node.")
            color: root.selectedProfile?.runtimeError || (root.selectedProfile?.enabled && !root.selectedProfile?.runtimeActive)
                ? Appearance.colors.colError
                : root.selectedProfile?.runtimeActive
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }
    }

    ContentSection {
        icon: "show_chart"
        title: Translation.tr("Frequency response curve")

        Loader {
            id: curveLoader
            Layout.fillWidth: true
            source: "EqCurveView.qml"

            Binding {
                target: curveLoader.item
                property: "profile"
                value: root.selectedProfile
            }
        }
    }

    ContentSection {
        icon: "compare_arrows"
        title: Translation.tr("Live A/B switching")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Enable and bypass update the PipeWire device node directly. Playback continues without restarting WirePlumber, and the selected state is also saved for the next device connection.")
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: PipewireEq.busy
            text: Translation.tr("Working…")
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: PipewireEq.lastMessage.length > 0
            text: PipewireEq.lastMessage
            color: Appearance.colors.colPrimary
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            visible: PipewireEq.lastError.length > 0
            text: PipewireEq.lastError
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
        }
    }
}
