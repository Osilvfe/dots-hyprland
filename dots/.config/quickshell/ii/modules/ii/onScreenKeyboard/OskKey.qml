import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

RippleButton {
    id: root
    property var keyData
    property string key: keyData.label
    property string type: keyData.keytype
    property var keycode: keyData.keycode
    property string shape: keyData.shape
    property bool isShift: VirtualKeyboard.shiftKeys.includes(keycode)
    property bool isModifier: root.type == "modkey"
    property bool isBackspace: (key.toLowerCase() == "backspace")
    property bool isEnter: (key.toLowerCase() == "enter" || key.toLowerCase() == "return")
    property bool modifierWasActive: false
    property real baseWidth: 45
    property real baseHeight: Orientation.isPortrait ? 52 : 45
    property var widthMultiplier: ({
        "normal": 1,
        "fn": 1,
        "tab": 1.6,
        "caps": 1.9,
        "shift": 2.5,
        "control": 1.3
    })
    property var heightMultiplier: ({
        "normal": 1,
        "fn": 0.7,
        "tab": 1,
        "caps": 1,
        "shift": 1,
        "control": 1
    })
    toggled: isModifier ? VirtualKeyboard.isModifierActive(keycode) : false

    enabled: shape != "empty"
    colBackground: shape == "empty" ? ColorUtils.transparentize(Appearance.colors.colLayer1) : Appearance.colors.colLayer1
    buttonRadius: Appearance.rounding.small
    implicitWidth: baseWidth * widthMultiplier[shape] || baseWidth
    implicitHeight: baseHeight * heightMultiplier[shape] || baseHeight
    Layout.fillWidth: shape == "space" || shape == "expand"

    Connections {
        target: VirtualKeyboard
        enabled: isShift
        function onShiftModeChanged() {
            if (VirtualKeyboard.shiftMode == 0) {
                capsLockTimer.hasStarted = false;
            }
        }
    }

    Timer {
        id: capsLockTimer
        property bool hasStarted: false
        property bool canCaps: false
        interval: 300
        function startWaiting() {
            hasStarted = true;
            canCaps = true;
            start();
        }
        onTriggered: {
            canCaps = false;
        }
    }

    Timer {
        id: repeatDelay
        interval: 450
        onTriggered: repeatTimer.start()
    }

    Timer {
        id: repeatTimer
        interval: 55
        repeat: true
        onTriggered: root.sendKey()
    }

    function outputText(): string {
        if (VirtualKeyboard.altGrActive && root.keyData.labelAlt !== undefined && root.keyData.labelAlt !== "") {
            return root.keyData.labelAlt;
        }
        if (VirtualKeyboard.shiftMode !== 0) {
            return root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label;
        }
        return root.keyData.label || "";
    }

    function sendKey(): void {
        VirtualKeyboard.press(root.keycode, root.outputText());
    }

    downAction: () => {
        if (root.isModifier && !root.isShift) {
            root.modifierWasActive = VirtualKeyboard.isModifierActive(root.keycode);
            if (root.modifierWasActive) {
                VirtualKeyboard.release(root.keycode);
            } else {
                VirtualKeyboard.press(root.keycode, "");
            }
        } else {
            root.sendKey();
        }
        if (isShift && VirtualKeyboard.shiftMode == 0) VirtualKeyboard.shiftMode = 1;
        if (root.type == "normal") repeatDelay.start();
    }
    releaseAction: () => {
        repeatDelay.stop();
        repeatTimer.stop();
        if (root.type == "normal") {
            if (VirtualKeyboard.shiftMode == 1) {
                VirtualKeyboard.releaseShiftKeys()
            }
        } else if (isShift) {
            if (VirtualKeyboard.shiftMode == 1) {
                if (!capsLockTimer.hasStarted) {
                    capsLockTimer.startWaiting();
                } else {
                    if (capsLockTimer.canCaps) {
                        VirtualKeyboard.shiftMode = 2; // Caps lock mode
                    } else {
                        VirtualKeyboard.releaseShiftKeys()
                    }
                }
            } else if (VirtualKeyboard.shiftMode == 2) {
                VirtualKeyboard.releaseShiftKeys();
            }
        }
    }

    contentItem: StyledText {
        id: keyText
        anchors.fill: parent
        font.family: (isBackspace || isEnter) ? Appearance.font.family.iconMaterial : Appearance.font.family.main
        font.pixelSize: root.shape == "fn" ? Appearance.font.pixelSize.small : 
            (isBackspace || isEnter) ? Appearance.font.pixelSize.huge :
            Appearance.font.pixelSize.large
        horizontalAlignment: Text.AlignHCenter
        color: root.toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        text: root.isBackspace ? "backspace" : root.isEnter ? "subdirectory_arrow_left" :
            VirtualKeyboard.altGrActive && root.keyData.labelAlt ? root.keyData.labelAlt :
            VirtualKeyboard.shiftMode == 2 ? (root.keyData.labelCaps || root.keyData.labelShift || root.keyData.label) :
            VirtualKeyboard.shiftMode == 1 ? (root.keyData.labelShift || root.keyData.label) :
            root.keyData.label
    }
}
