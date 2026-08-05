pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    property bool recordSystem: false
    property bool recordMic: false
    property string recordArea: "region" // region | fullscreen | window
    property bool areaDropdownOpen: false

    property var areaOptions: [
        { icon: "crop_free", label: Translation.tr("区域"), value: "region" },
        { icon: "fullscreen", label: Translation.tr("全屏"), value: "fullscreen" },
        { icon: "select_window", label: Translation.tr("窗口"), value: "window" },
    ]
    readonly property var currentArea: {
        for (const opt of root.areaOptions) {
            if (opt.value === root.recordArea) return opt;
        }
        return root.areaOptions[0];
    }

    function startRecording() {
        var cmd = Directories.recordScriptPath;
        if (root.recordSystem) cmd += " --audio-src $(pactl get-default-sink).monitor";
        if (root.recordMic) cmd += " --audio-src $(pactl get-default-source)";
        if (root.recordArea === "fullscreen") cmd += " --fullscreen";
        else if (root.recordArea === "window") cmd += " --window";
        Quickshell.execDetached(["bash", "-c", cmd]);
        GlobalStates.recordingMenuOpen = false;
    }

    Loader {
        id: menuLoader
        active: GlobalStates.recordingMenuOpen

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            implicitWidth: menuBackground.implicitWidth + 24
            implicitHeight: menuBackground.implicitHeight + 16
            color: "transparent"
            WlrLayershell.namespace: "quickshell:recordingMenu"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            anchors {
                top: false
                bottom: true
                left: true
                right: true
            }
            margins {
                bottom: 130
            }

            mask: Region {
                item: menuBackground
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
                    GlobalStates.recordingMenuOpen = false;
                }
            }

            Rectangle {
                id: menuBackground
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                radius: 20
                color: Appearance.m3colors.m3surfaceContainer
                border.width: 1
                border.color: Appearance.colors.colLayer1Border
                implicitWidth: 260
                implicitHeight: menuColumn.implicitHeight + 20

                ColumnLayout {
                    id: menuColumn
                    anchors.margins: 10
                    anchors.fill: parent
                    spacing: 4

                    StyledComboBox {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 2
                        model: [
                            Translation.tr("区域"),
                            Translation.tr("全屏"),
                            Translation.tr("窗口"),
                        ]
                        currentIndex: root.recordArea === "region" ? 0
                            : root.recordArea === "fullscreen" ? 1 : 2
                        onActivated: (index) => {
                            root.recordArea = index === 0 ? "region"
                                : index === 1 ? "fullscreen" : "window";
                        }
                    }

                    StyledText {
                        Layout.leftMargin: 6
                        Layout.topMargin: 6
                        Layout.bottomMargin: 2
                        text: Translation.tr("录音")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnSurfaceVariant
                    }

                    ConfigSwitch {
                        buttonIcon: "speaker"
                        text: Translation.tr("系统声音")
                        checked: root.recordSystem
                        onClicked: root.recordSystem = !root.recordSystem
                    }
                    ConfigSwitch {
                        buttonIcon: "mic"
                        text: Translation.tr("麦克风")
                        checked: root.recordMic
                        onClicked: root.recordMic = !root.recordMic
                    }

                    RowLayout {
                        Layout.topMargin: 8
                        Layout.fillWidth: true
                        implicitHeight: 32
                        spacing: 10

                        MaterialSymbol {
                            text: "play_arrow"
                            iconSize: 20
                            color: Appearance.colors.colPrimary
                        }

                        StyledText {
                            text: Translation.tr("开始录制")
                            font.pixelSize: Appearance.font.pixelSize.medium
                            color: Appearance.colors.colPrimary
                            Layout.fillWidth: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.startRecording()
                        }
                    }
                }
            }
        }
    }
}
