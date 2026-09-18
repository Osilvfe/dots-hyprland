pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    readonly property bool fluidEnabled: Config.options.appearance.fluidMorphing.enable ?? false
    readonly property real osdWidth: Appearance.sizes.osdWidth
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    property real popupRounding: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

    Loader {
        id: mediaControlsLoader
        // 在流体形态模式开启时，禁用此独立 PanelWindow，由 Drawers.qml 统一流体接管
        active: GlobalStates.mediaControlsOpen && !root.fluidEnabled

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true
            screen: GlobalStates.mediaButtonScreen ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: root.widgetWidth
            implicitHeight: contentItem.contentHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:mediaControls"

            anchors {
                top: !Config.options.bar.bottom || Config.options.bar.vertical
                bottom: Config.options.bar.bottom && !Config.options.bar.vertical
                left: !(Config.options.bar.vertical && Config.options.bar.bottom)
                right: Config.options.bar.vertical && Config.options.bar.bottom
            }
            margins {
                top: Config.options.bar.vertical ? ((panelWindow.screen.height / 2) - widgetHeight * 1.5) : Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
                left: {
                    if (Config.options.bar.vertical) {
                        return Appearance.sizes.barHeight;
                    }
                    const isCurrentScreen = !GlobalStates.mediaButtonScreen || GlobalStates.mediaButtonScreen === panelWindow.screen;
                    if (isCurrentScreen && GlobalStates.mediaCenterX > 0) {
                        const minLeft = Appearance.sizes.hyprlandGapsOut;
                        const maxLeft = Math.max(minLeft, (panelWindow.screen?.width ?? 1920) - root.widgetWidth - Appearance.sizes.hyprlandGapsOut);
                        const targetLeft = GlobalStates.mediaCenterX - (root.widgetWidth / 2);
                        return Math.max(minLeft, Math.min(maxLeft, targetLeft));
                    }
                    return ((panelWindow.screen.width / 2) - (osdWidth / 2) - widgetWidth);
                }
                right: Appearance.sizes.barHeight
            }

            mask: Region {
                item: contentItem
            }

            Component.onCompleted: {
                GlobalFocusGrab.addDismissable(panelWindow);
            }
            Component.onDestruction: {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
            Connections {
                target: GlobalFocusGrab
                function onDismissed() {
                    GlobalStates.mediaControlsOpen = false;
                }
            }

            MediaControlsContent {
                id: contentItem
                anchors.fill: parent
                active: mediaControlsLoader.active
                popupRounding: root.popupRounding
            }
        }
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
            if (GlobalStates.mediaControlsOpen)
                Notifications.timeoutAll();
        }

        function close(): void {
            GlobalStates.mediaControlsOpen = false;
        }

        function open(): void {
            GlobalStates.mediaControlsOpen = true;
            Notifications.timeoutAll();
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
        }
    }
    GlobalShortcut {
        name: "mediaControlsOpen"
        description: "Opens media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = true;
        }
    }
    GlobalShortcut {
        name: "mediaControlsClose"
        description: "Closes media controls on press"

        onPressed: {
            GlobalStates.mediaControlsOpen = false;
        }
    }
}
