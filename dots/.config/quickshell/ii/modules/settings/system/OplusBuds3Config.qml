import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root

    signal backRequested()

    Layout.fillWidth: true
    spacing: 12

    Component.onCompleted: OplusBuds3.activate()
    Component.onDestruction: OplusBuds3.deactivate()

    component BudsBatteryCard: Rectangle {
        id: batteryCard

        required property string label
        required property int level
        property bool charging: false

        Layout.fillWidth: true
        implicitHeight: 62
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 1

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: batteryCard.level >= 0 ? `${batteryCard.level}%${batteryCard.charging ? " ⚡" : ""}` : "—"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: batteryCard.label
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Appearance.colors.colSubtext
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true

        DialogButton {
            buttonText: Translation.tr("Back")
            onClicked: root.backRequested()
        }

        Item {
            Layout.fillWidth: true
        }
    }

    ContentSection {
        icon: "headphones"
        title: Translation.tr("OnePlus Buds 3 controls")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                text: OplusBuds3.connected
                    ? Translation.tr("Control channel connected")
                    : OplusBuds3.connecting
                        ? Translation.tr("Connecting to earbud controls...")
                        : (OplusBuds3.lastError || Translation.tr("Control channel disconnected"))
                color: OplusBuds3.connected ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            DialogButton {
                buttonText: Translation.tr("Reconnect")
                enabled: OplusBuds3.available
                onClicked: OplusBuds3.restart()
            }

            DialogButton {
                buttonText: Translation.tr("Refresh")
                enabled: OplusBuds3.connected
                onClicked: OplusBuds3.refresh()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            BudsBatteryCard {
                label: Translation.tr("Left earbud")
                level: OplusBuds3.batteryLeft
                charging: OplusBuds3.chargingLeft
            }
            BudsBatteryCard {
                label: Translation.tr("Charging case")
                level: OplusBuds3.batteryCase
                charging: OplusBuds3.chargingCase
            }
            BudsBatteryCard {
                label: Translation.tr("Right earbud")
                level: OplusBuds3.batteryRight
                charging: OplusBuds3.chargingRight
            }
        }

        ContentSubsection {
            title: Translation.tr("Noise control")

            ConfigSelectionArray {
                enabled: OplusBuds3.connected
                currentValue: OplusBuds3.ancMode
                onSelected: mode => OplusBuds3.setAnc(mode)
                options: [
                    { displayName: Translation.tr("Off"), icon: "noise_control_off", value: "off" },
                    { displayName: Translation.tr("Smart"), icon: "auto_awesome", value: "smart" },
                    { displayName: Translation.tr("Deep ANC"), icon: "noise_aware", value: "deep" },
                    { displayName: Translation.tr("Medium ANC"), icon: "noise_aware", value: "medium" },
                    { displayName: Translation.tr("Light ANC"), icon: "noise_aware", value: "light" },
                    { displayName: Translation.tr("Transparency mode"), icon: "hearing", value: "transparency" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Equalizer")

            ConfigSelectionArray {
                enabled: OplusBuds3.connected
                currentValue: OplusBuds3.eqPreset
                onSelected: preset => OplusBuds3.setEq(preset)
                options: [
                    { displayName: Translation.tr("Balanced"), icon: "equalizer", value: 0 },
                    { displayName: Translation.tr("Deep bass"), icon: "graphic_eq", value: 1 },
                    { displayName: Translation.tr("Clear vocals"), icon: "record_voice_over", value: 2 },
                    { displayName: Translation.tr("Bright and clear"), icon: "flare", value: 3 }
                ]
            }
        }

        ConfigSwitch {
            enabled: OplusBuds3.connected && OplusBuds3.hiRes >= 0
            buttonIcon: "high_quality"
            text: Translation.tr("Hi-Res audio")
            checked: OplusBuds3.hiRes === 1
            onCheckedChanged: {
                if (enabled && checked !== (OplusBuds3.hiRes === 1))
                    OplusBuds3.setHiRes(checked);
            }

            StyledToolTip {
                text: Translation.tr("Enables the earbuds' LHDC Hi-Res mode. The actual codec, sample rate and bitrate are negotiated by the host.")
            }
        }

        ConfigSwitch {
            enabled: OplusBuds3.connected && OplusBuds3.spatial >= 0
            buttonIcon: "spatial_audio"
            text: Translation.tr("Spatial audio")
            checked: OplusBuds3.spatial === 1
            onCheckedChanged: {
                if (enabled && checked !== (OplusBuds3.spatial === 1))
                    OplusBuds3.setSpatial(checked);
            }
        }

        ConfigSwitch {
            enabled: OplusBuds3.connected && OplusBuds3.gameMode >= 0
            buttonIcon: "sports_esports"
            text: Translation.tr("Game mode")
            checked: OplusBuds3.gameMode === 1
            onCheckedChanged: {
                if (enabled && checked !== (OplusBuds3.gameMode === 1))
                    OplusBuds3.setGameMode(checked);
            }
        }

        ConfigSwitch {
            enabled: OplusBuds3.connected && OplusBuds3.gameSound >= 0
            buttonIcon: "stadia_controller"
            text: Translation.tr("Game sound")
            checked: OplusBuds3.gameSound === 1
            onCheckedChanged: {
                if (enabled && checked !== (OplusBuds3.gameSound === 1))
                    OplusBuds3.setGameSound(checked);
            }
        }

        ConfigSwitch {
            enabled: OplusBuds3.connected && OplusBuds3.dualDevice >= 0
            buttonIcon: "devices"
            text: Translation.tr("Dual-device connection")
            checked: OplusBuds3.dualDevice === 1
            onCheckedChanged: {
                if (enabled && checked !== (OplusBuds3.dualDevice === 1))
                    OplusBuds3.setDualDevice(checked);
            }
        }

        ConfigSwitch {
            enabled: OplusBuds3.connected && OplusBuds3.wearDetection >= 0
            buttonIcon: "earbuds"
            text: Translation.tr("Wear detection")
            checked: OplusBuds3.wearDetection === 1
            onCheckedChanged: {
                if (enabled && checked !== (OplusBuds3.wearDetection === 1))
                    OplusBuds3.setWearDetection(checked);
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: OplusBuds3.gameSound === 1
            text: Translation.tr("Game sound is mutually exclusive with spatial audio and non-default EQ modes.")
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smallie
            wrapMode: Text.Wrap
        }
    }
}
