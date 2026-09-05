import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    forceWidth: true

    signal openPageRequested(int pageIndex)

    readonly property var outputDevices: Audio.outputDevices
    readonly property var inputDevices: Audio.inputDevices
    readonly property var outputApps: Audio.outputAppNodes
    readonly property var inputApps: Audio.inputAppNodes
    property int appMixerMode: 0 // 0: Playback, 1: Recording

    PwObjectTracker {
        objects: [Audio.sink, Audio.source]
    }

    function playTestSound(soundName) {
        const theme = Config.options.sounds.theme || "freedesktop";
        const cmd = `
            oga="/usr/share/sounds/${theme}/stereo/${soundName}.oga"
            ogg="/usr/share/sounds/${theme}/stereo/${soundName}.ogg"
            fb_oga="/usr/share/sounds/freedesktop/stereo/${soundName}.oga"
            fb_ogg="/usr/share/sounds/freedesktop/stereo/${soundName}.ogg"
            if [ -f "$oga" ]; then
                ffplay -nodisp -autoexit "$oga" 2>/dev/null
            elif [ -f "$ogg" ]; then
                ffplay -nodisp -autoexit "$ogg" 2>/dev/null
            elif [ -f "$fb_oga" ]; then
                ffplay -nodisp -autoexit "$fb_oga" 2>/dev/null
            elif [ -f "$fb_ogg" ]; then
                ffplay -nodisp -autoexit "$fb_ogg" 2>/dev/null
            fi
        `;
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    // -------------------------------------------------------------
    // Header & Quick Action
    // -------------------------------------------------------------
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            OptionalMaterialSymbol {
                icon: "volume_up"
                iconSize: Appearance.font.pixelSize.hugeass
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Sound")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Medium
                color: Appearance.colors.colOnSecondaryContainer
            }

            DialogButton {
                buttonText: Translation.tr("Advanced settings")
                onClicked: Quickshell.execDetached(["bash", "-c", Config.options.apps.volumeMixer])
            }
        }
    }

    // -------------------------------------------------------------
    // Output Section
    // -------------------------------------------------------------
    ContentSection {
        icon: "volume_up"
        title: Translation.tr("Output")

        ConfigRow {
            StyledText {
                text: Translation.tr("Output device")
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledComboBox {
                Layout.fillWidth: true
                model: root.outputDevices.map(node => Audio.friendlyDeviceName(node))
                currentIndex: {
                    const idx = root.outputDevices.findIndex(node => node.id === Pipewire.defaultAudioSink?.id);
                    return idx >= 0 ? idx : 0;
                }
                onActivated: (index) => {
                    if (index >= 0 && index < root.outputDevices.length) {
                        Audio.setDefaultSink(root.outputDevices[index]);
                    }
                }
            }
        }

        ConfigRow {
            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: (Audio.sink?.audio?.muted ?? false)
                    ? Appearance.colors.colErrorContainer
                    : Appearance.colors.colPrimaryContainer
                colBackgroundHover: (Audio.sink?.audio?.muted ?? false)
                    ? Appearance.colors.colErrorHover
                    : Appearance.colors.colPrimaryHover
                onClicked: Audio.toggleMute()

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    text: {
                        if (Audio.sink?.audio?.muted ?? false) return "volume_off";
                        const vol = Audio.sink?.audio?.volume ?? 0;
                        if (vol <= 0.01) return "volume_mute";
                        if (vol < 0.5) return "volume_down";
                        return "volume_up";
                    }
                    color: (Audio.sink?.audio?.muted ?? false)
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                }

                StyledToolTip {
                    text: (Audio.sink?.audio?.muted ?? false)
                        ? Translation.tr("Unmute output")
                        : Translation.tr("Mute output")
                }
            }

            StyledText {
                text: Translation.tr("Master volume")
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: Math.max(1.0, (Config.options.audio.osdMaxPercent ?? 150) / 100)
                value: Audio.sink?.audio?.volume ?? 0
                onMoved: {
                    if (Audio.sink?.audio) {
                        Audio.sink.audio.volume = value;
                    }
                }
                configuration: StyledSlider.Configuration.S
            }

            StyledText {
                text: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}%`
                font.family: Appearance.font.family.monospace
                font.weight: Font.Medium
                color: (Audio.sink?.audio?.muted ?? false)
                    ? Appearance.colors.colSubtext
                    : Appearance.colors.colPrimary
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignRight
            }
        }

        ConfigRow {
            StyledText {
                text: Translation.tr("Speaker test")
                color: Appearance.colors.colSubtext
            }

            Item {
                Layout.fillWidth: true
            }

            DialogButton {
                padding: 10
                implicitHeight: 30
                buttonText: Translation.tr("Left channel")
                onClicked: root.playTestSound("audio-channel-front-left")
            }

            DialogButton {
                padding: 10
                implicitHeight: 30
                buttonText: Translation.tr("Right channel")
                onClicked: root.playTestSound("audio-channel-front-right")
            }

            DialogButton {
                padding: 10
                implicitHeight: 30
                buttonText: Translation.tr("Chime")
                onClicked: root.playTestSound("audio-volume-change")
            }
        }
    }

    // -------------------------------------------------------------
    // Input Section
    // -------------------------------------------------------------
    ContentSection {
        icon: "mic"
        title: Translation.tr("Input")

        ConfigRow {
            StyledText {
                text: Translation.tr("Input device")
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledComboBox {
                Layout.fillWidth: true
                model: root.inputDevices.map(node => Audio.friendlyDeviceName(node))
                currentIndex: {
                    const idx = root.inputDevices.findIndex(node => node.id === Pipewire.defaultAudioSource?.id);
                    return idx >= 0 ? idx : 0;
                }
                onActivated: (index) => {
                    if (index >= 0 && index < root.inputDevices.length) {
                        Audio.setDefaultSource(root.inputDevices[index]);
                    }
                }
            }
        }

        ConfigRow {
            RippleButton {
                implicitWidth: 36
                implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                colBackground: (Audio.source?.audio?.muted ?? false)
                    ? Appearance.colors.colErrorContainer
                    : Appearance.colors.colPrimaryContainer
                colBackgroundHover: (Audio.source?.audio?.muted ?? false)
                    ? Appearance.colors.colErrorHover
                    : Appearance.colors.colPrimaryHover
                onClicked: Audio.toggleMicMute()

                MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    text: (Audio.source?.audio?.muted ?? false) ? "mic_off" : "mic"
                    color: (Audio.source?.audio?.muted ?? false)
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnPrimaryContainer
                }

                StyledToolTip {
                    text: (Audio.source?.audio?.muted ?? false)
                        ? Translation.tr("Unmute microphone")
                        : Translation.tr("Mute microphone")
                }
            }

            StyledText {
                text: Translation.tr("Input volume")
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: 1.0
                value: Audio.source?.audio?.volume ?? 0
                onMoved: {
                    if (Audio.source?.audio) {
                        Audio.source.audio.volume = value;
                    }
                }
                configuration: StyledSlider.Configuration.S
            }

            StyledText {
                text: `${Math.round((Audio.source?.audio?.volume ?? 0) * 100)}%`
                font.family: Appearance.font.family.monospace
                font.weight: Font.Medium
                color: (Audio.source?.audio?.muted ?? false)
                    ? Appearance.colors.colSubtext
                    : Appearance.colors.colPrimary
                Layout.preferredWidth: 42
                horizontalAlignment: Text.AlignRight
            }
        }

        RowLayout {
            spacing: 8
            Layout.leftMargin: 8

            Rectangle {
                width: 7
                height: 7
                radius: 3.5
                color: Privacy.micActive ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            StyledText {
                text: Privacy.micActive ? Translation.tr("Microphone is in use") : Translation.tr("Microphone is idle")
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: Privacy.micActive ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
        }
    }

    // -------------------------------------------------------------
    // Application Volume Mixer Section
    // -------------------------------------------------------------
    ContentSection {
        icon: "tune"
        title: Translation.tr("Application volume")

        SecondaryTabBar {
            id: appMixerTabBar
            Layout.fillWidth: true
            currentIndex: root.appMixerMode
            onCurrentIndexChanged: root.appMixerMode = appMixerTabBar.currentIndex

            SecondaryTabButton {
                buttonIcon: "media_output"
                buttonText: Translation.tr("Playback (%1)").arg(root.outputApps.length)
            }
            SecondaryTabButton {
                buttonIcon: "mic"
                buttonText: Translation.tr("Recording (%1)").arg(root.inputApps.length)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 6

            Repeater {
                model: ScriptModel {
                    values: root.appMixerMode === 0 ? root.outputApps : root.inputApps
                }
                delegate: AppVolumeItem {
                    required property var modelData
                    node: modelData
                    isSink: root.appMixerMode === 0
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 140
                visible: (root.appMixerMode === 0 ? root.outputApps.length : root.inputApps.length) === 0

                PagePlaceholder {
                    icon: root.appMixerMode === 0 ? "volume_off" : "mic_off"
                    title: root.appMixerMode === 0
                        ? Translation.tr("No applications currently playing audio")
                        : Translation.tr("No applications currently recording audio")
                    shape: MaterialShape.Shape.Cookie7Sided
                    shown: parent.visible
                }
            }
        }
    }

    // -------------------------------------------------------------
    // System Sounds Section
    // -------------------------------------------------------------
    ContentSection {
        icon: "notification_sound"
        title: Translation.tr("System sounds")

        ConfigRow {
            StyledText {
                text: Translation.tr("Sound theme")
                color: Appearance.colors.colOnSecondaryContainer
            }

            StyledComboBox {
                Layout.fillWidth: true
                model: ["freedesktop", "ocean", "oxygen"]
                currentIndex: {
                    const idx = model.indexOf(Config.options.sounds.theme);
                    return idx >= 0 ? idx : 0;
                }
                onActivated: (index) => {
                    Config.options.sounds.theme = model[index];
                }
            }
        }

        ConfigRow {
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "notifications"
                text: Translation.tr("Notification sound")
                checked: Config.options.sounds.notifications
                onCheckedChanged: {
                    Config.options.sounds.notifications = checked;
                }
            }

            DialogButton {
                padding: 10
                implicitHeight: 30
                buttonText: Translation.tr("Test")
                onClicked: root.playTestSound("message-new-instant")
            }
        }

        ConfigRow {
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "battery_android_full"
                text: Translation.tr("Battery warning sound")
                checked: Config.options.sounds.battery
                onCheckedChanged: {
                    Config.options.sounds.battery = checked;
                }
            }

            DialogButton {
                padding: 10
                implicitHeight: 30
                buttonText: Translation.tr("Test")
                onClicked: root.playTestSound("power-unplug")
            }
        }

        ConfigRow {
            ConfigSwitch {
                Layout.fillWidth: true
                buttonIcon: "av_timer"
                text: Translation.tr("Pomodoro timer sound")
                checked: Config.options.sounds.pomodoro
                onCheckedChanged: {
                    Config.options.sounds.pomodoro = checked;
                }
            }

            DialogButton {
                padding: 10
                implicitHeight: 30
                buttonText: Translation.tr("Test")
                onClicked: root.playTestSound("alarm-clock-elapsed")
            }
        }
    }

    // -------------------------------------------------------------
    // Volume Protection & Limits
    // -------------------------------------------------------------
    ContentSection {
        icon: "hearing"
        title: Translation.tr("Volume protection & limits")

        ConfigSwitch {
            buttonIcon: "hearing"
            text: Translation.tr("Earbang protection")
            checked: Config.options.audio.protection.enable
            onCheckedChanged: {
                Config.options.audio.protection.enable = checked;
            }
            StyledToolTip {
                text: Translation.tr("Prevents abrupt increments and restricts volume limit")
            }
        }

        ConfigRow {
            uniform: true
            enabled: Config.options.audio.protection.enable
            opacity: enabled ? 1.0 : 0.45

            ConfigSpinBox {
                icon: "arrow_warm_up"
                text: Translation.tr("Max allowed increase")
                value: Config.options.audio.protection.maxAllowedIncrease
                from: 0
                to: 100
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowedIncrease = value;
                }
            }

            ConfigSpinBox {
                icon: "vertical_align_top"
                text: Translation.tr("Volume limit")
                value: Config.options.audio.protection.maxAllowed
                from: 0
                to: 154
                stepSize: 2
                onValueChanged: {
                    Config.options.audio.protection.maxAllowed = value;
                }
            }
        }

        ConfigSpinBox {
            icon: "volume_up"
            text: Translation.tr("OSD / bar-scroll volume ceiling (%)")
            value: Config.options.audio.osdMaxPercent
            from: 100
            to: 150
            stepSize: 10
            onValueChanged: {
                Config.options.audio.osdMaxPercent = value;
            }
        }
    }

    // -------------------------------------------------------------
    // Component: App Volume Entry Item
    // -------------------------------------------------------------
    component AppVolumeItem: Item {
        id: appItemRoot
        required property PwNode node
        required property bool isSink

        PwObjectTracker {
            objects: [appItemRoot.node]
        }

        Layout.fillWidth: true
        implicitHeight: appRowLayout.implicitHeight + 8

        RowLayout {
            id: appRowLayout
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 8
                rightMargin: 8
            }
            spacing: 10

            MouseArea {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                    if (appItemRoot.node?.audio) {
                        appItemRoot.node.audio.muted = !appItemRoot.node.audio.muted;
                    }
                }

                StyledToolTip {
                    text: (appItemRoot.node?.audio?.muted ?? false)
                        ? Translation.tr("Click to unmute")
                        : Translation.tr("Click to mute")
                }

                StyledImage {
                    id: appIcon
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    source: {
                        let icon = AppSearch.guessIcon(appItemRoot.node?.properties["application.icon-name"] ?? "");
                        if (AppSearch.iconExists(icon))
                            return Quickshell.iconPath(icon, "image-missing");
                        icon = AppSearch.guessIcon(appItemRoot.node?.properties["node.name"] ?? "");
                        return Quickshell.iconPath(icon, "image-missing");
                    }
                    visible: source !== ""
                    opacity: (appItemRoot.node?.audio?.muted ?? false) ? 0.35 : 1.0
                }

                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: (appItemRoot.node?.audio?.muted ?? false) || appIcon.source === ""
                    text: (appItemRoot.node?.audio?.muted ?? false)
                        ? (appItemRoot.isSink ? "volume_off" : "mic_off")
                        : (appItemRoot.isSink ? "audiotrack" : "mic")
                    iconSize: 20
                    color: (appItemRoot.node?.audio?.muted ?? false)
                        ? Appearance.colors.colOnErrorContainer
                        : Appearance.colors.colOnSecondaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            const app = Audio.appNodeDisplayName(appItemRoot.node);
                            const media = appItemRoot.node?.properties?.["media.name"];
                            return (media !== undefined && media !== "") ? `${app} · ${media}` : app;
                        }
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        text: `${Math.round((appItemRoot.node?.audio?.volume ?? 0) * 100)}%`
                        color: (appItemRoot.node?.audio?.muted ?? false)
                            ? Appearance.colors.colSubtext
                            : Appearance.colors.colPrimary
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.monospace
                        Layout.preferredWidth: 42
                        horizontalAlignment: Text.AlignRight
                    }
                }

                StyledSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1.0
                    value: appItemRoot.node?.audio?.volume ?? 0
                    onMoved: {
                        if (appItemRoot.node?.audio) {
                            appItemRoot.node.audio.volume = value;
                        }
                    }
                    configuration: StyledSlider.Configuration.XS
                }
            }
        }
    }
}

