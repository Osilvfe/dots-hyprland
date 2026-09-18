import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    property string currentIndicator: "volume"
    property var indicators: [
        {
            id: "volume",
            sourceUrl: "indicators/VolumeIndicator.qml"
        },
        {
            id: "brightness",
            sourceUrl: "indicators/BrightnessIndicator.qml"
        },
        {
            id: "gamma",
            sourceUrl: "indicators/GammaIndicator.qml"
        },
    ]

    readonly property bool fluidEnabled: Config.options.appearance.fluidMorphing.enable ?? false

    function triggerOsd(indicator, protection) {
        if (indicator) {
            root.currentIndicator = indicator;
            GlobalStates.osdIndicator = indicator;
        }
        root.protectionMessage = protection ?? "";
        GlobalStates.osdProtectionMessage = root.protectionMessage;
        GlobalStates.osdVolumeOpen = true;
        osdTimeout.restart();
    }

    Timer {
        id: osdTimeout
        interval: Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            GlobalStates.osdVolumeOpen = false;
            root.protectionMessage = "";
            GlobalStates.osdProtectionMessage = "";
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.triggerOsd("brightness", "");
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            root.triggerOsd("gamma", "");
        }
    }

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready)
                return;
            root.triggerOsd("volume", "");
        }
        function onMutedChanged() {
            if (!Audio.ready)
                return;
            root.triggerOsd("volume", "");
        }
    }

    Connections {
        // Listen to protection triggers
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.triggerOsd("volume", reason);
        }
    }

    Loader {
        id: osdLoader
        active: GlobalStates.osdVolumeOpen && !root.fluidEnabled

        sourceComponent: PanelWindow {
            id: osdRoot
            screen: root.focusedScreen ?? Quickshell.screens[0]
            color: "transparent"

            Connections {
                target: root
                function onFocusedScreenChanged() {
                    osdRoot.screen = root.focusedScreen;
                }
            }

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.bar.bottom
                bottom: Config.options.bar.bottom
            }
            mask: Region {
                item: osdContent
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            margins {
                top: Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
            }

            implicitWidth: osdContent.implicitWidth
            implicitHeight: osdContent.implicitHeight
            visible: osdLoader.active

            OsdContent {
                id: osdContent
                anchors.centerIn: parent
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            GlobalStates.osdVolumeOpen = false;
        }

        function toggle() {
            GlobalStates.osdVolumeOpen = !GlobalStates.osdVolumeOpen;
        }
    }
    GlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    GlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            GlobalStates.osdVolumeOpen = false;
        }
    }
}
