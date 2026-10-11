pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock
import qs.services

Rectangle {
    id: root
    required property LockContext context
    property bool ctrlHeld: false
    signal closeRequested()

    property bool shiftActive: false
    property bool symbolMode: false
    property bool numpadMode: false

    function appendChar(ch: string): void {
        root.context.currentText += ch;
        root.context.resetClearTimer();
        if (root.shiftActive) {
            root.shiftActive = false;
        }
    }

    function backspace(): void {
        if (root.context.currentText.length > 0) {
            root.context.currentText = root.context.currentText.slice(0, -1);
            root.context.resetClearTimer();
        }
    }

    function clear(): void {
        root.context.currentText = "";
        root.context.resetClearTimer();
    }

    function submit(): void {
        root.context.tryUnlock(root.ctrlHeld);
    }

    color: Appearance.colors.colLayer0
    radius: Appearance.rounding.windowRounding
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    implicitWidth: root.numpadMode ? 340 : Math.min(parent ? parent.width - 40 : 680, 680)
    implicitHeight: mainCol.implicitHeight + 20

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: mainCol
        anchors {
            fill: parent
            margins: 10
        }
        spacing: 6

        // Top bar: Mode switcher & close handle
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            RippleButton {
                implicitHeight: 28
                implicitWidth: 84
                buttonRadius: Appearance.rounding.small
                colBackground: root.numpadMode ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                onClicked: root.numpadMode = !root.numpadMode

                contentItem: RowLayout {
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        iconSize: 15
                        text: root.numpadMode ? "keyboard" : "dialpad"
                        color: root.numpadMode ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: root.numpadMode ? Translation.tr("QWERTY") : Translation.tr("PIN")
                        color: root.numpadMode ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Minimize / dismiss handle
            RippleButton {
                implicitHeight: 28
                implicitWidth: 36
                buttonRadius: Appearance.rounding.small
                colBackground: Appearance.colors.colLayer2
                onClicked: root.closeRequested()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 18
                    text: "keyboard_hide"
                    color: Appearance.colors.colOnLayer2
                }
            }
        }

        // QWERTY Layout
        ColumnLayout {
            id: qwertyLayout
            visible: !root.numpadMode
            Layout.fillWidth: true
            spacing: 5

            // Row 1: Numbers
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
                    delegate: KeyBtn {
                        required property string modelData
                        label: modelData
                        onKeyTriggered: root.appendChar(modelData)
                    }
                }
            }

            // Row 2: Letters / Symbols (QWERTY)
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: root.symbolMode 
                        ? ["~", "`", "@", "#", "$", "%", "^", "&", "*", "("] 
                        : ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
                    delegate: KeyBtn {
                        required property string modelData
                        label: root.shiftActive ? modelData.toUpperCase() : modelData
                        onKeyTriggered: root.appendChar(label)
                    }
                }
            }

            // Row 3: Middle row
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Repeater {
                    model: root.symbolMode 
                        ? [")", "-", "_", "=", "+", "[", "]", "{", "}", "\\"] 
                        : ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
                    delegate: KeyBtn {
                        required property string modelData
                        label: root.shiftActive ? modelData.toUpperCase() : modelData
                        onKeyTriggered: root.appendChar(label)
                    }
                }
            }

            // Row 4: Shift, Bottom letters/symbols, Backspace
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                // Shift
                KeyBtn {
                    Layout.preferredWidth: 64
                    iconName: root.shiftActive ? "shift_lock" : "shift"
                    isToggled: root.shiftActive
                    onKeyTriggered: root.shiftActive = !root.shiftActive
                }

                Repeater {
                    model: root.symbolMode 
                        ? ["|", ";", ":", "\"", "'", "<", ">", "/", "?"] 
                        : ["z", "x", "c", "v", "b", "n", "m"]
                    delegate: KeyBtn {
                        required property string modelData
                        label: root.shiftActive ? modelData.toUpperCase() : modelData
                        onKeyTriggered: root.appendChar(label)
                    }
                }

                // Backspace
                BackspaceBtn {
                    Layout.preferredWidth: 64
                    onBsTriggered: root.backspace()
                }
            }

            // Row 5: ?123, Space, Clear, Unlock
            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                // ?123 symbol switch
                KeyBtn {
                    Layout.preferredWidth: 64
                    label: root.symbolMode ? "ABC" : "?123"
                    isToggled: root.symbolMode
                    onKeyTriggered: root.symbolMode = !root.symbolMode
                }

                KeyBtn {
                    Layout.preferredWidth: 42
                    label: ","
                    onKeyTriggered: root.appendChar(",")
                }

                // Spacebar
                KeyBtn {
                    Layout.fillWidth: true
                    label: Translation.tr("Space")
                    onKeyTriggered: root.appendChar(" ")
                }

                KeyBtn {
                    Layout.preferredWidth: 42
                    label: "."
                    onKeyTriggered: root.appendChar(".")
                }

                // Clear input
                KeyBtn {
                    Layout.preferredWidth: 54
                    iconName: "clear_all"
                    onKeyTriggered: root.clear()
                }

                // Unlock
                KeyBtn {
                    Layout.preferredWidth: 72
                    iconName: "arrow_right_alt"
                    isAccent: true
                    onKeyTriggered: root.submit()
                }
            }
        }

        // PIN Pad Layout
        ColumnLayout {
            id: pinLayout
            visible: root.numpadMode
            Layout.fillWidth: true
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: ["1", "2", "3"]
                    delegate: KeyBtn {
                        required property string modelData
                        implicitHeight: 46
                        label: modelData
                        onKeyTriggered: root.appendChar(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: ["4", "5", "6"]
                    delegate: KeyBtn {
                        required property string modelData
                        implicitHeight: 46
                        label: modelData
                        onKeyTriggered: root.appendChar(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: ["7", "8", "9"]
                    delegate: KeyBtn {
                        required property string modelData
                        implicitHeight: 46
                        label: modelData
                        onKeyTriggered: root.appendChar(modelData)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                KeyBtn {
                    implicitHeight: 46
                    iconName: "clear_all"
                    onKeyTriggered: root.clear()
                }

                KeyBtn {
                    implicitHeight: 46
                    label: "0"
                    onKeyTriggered: root.appendChar("0")
                }

                BackspaceBtn {
                    implicitHeight: 46
                    onBsTriggered: root.backspace()
                }
            }

            // Big Unlock button
            KeyBtn {
                Layout.fillWidth: true
                implicitHeight: 44
                iconName: "arrow_right_alt"
                isAccent: true
                onKeyTriggered: root.submit()
            }
        }
    }

    // Helper key button component
    component KeyBtn: RippleButton {
        id: keyBtn
        property string label: ""
        property string iconName: ""
        property bool isAccent: false
        property bool isToggled: false
        signal keyTriggered()

        implicitHeight: 40
        Layout.fillWidth: true
        buttonRadius: Appearance.rounding.small
        colBackground: isAccent 
            ? Appearance.colors.colPrimary 
            : (isToggled ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2)
        colBackgroundHover: isAccent 
            ? Appearance.colors.colPrimaryHover 
            : (isToggled ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover)

        onClicked: {
            keyTriggered();
        }

        contentItem: Item {
            anchors.fill: parent
            MaterialSymbol {
                visible: keyBtn.iconName !== ""
                anchors.centerIn: parent
                iconSize: 20
                text: keyBtn.iconName
                color: keyBtn.isAccent 
                    ? Appearance.colors.colOnPrimary 
                    : (keyBtn.isToggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2)
            }
            StyledText {
                visible: keyBtn.iconName === ""
                anchors.centerIn: parent
                font.pixelSize: Appearance.font.pixelSize.medium
                font.weight: Font.DemiBold
                text: keyBtn.label
                color: keyBtn.isAccent 
                    ? Appearance.colors.colOnPrimary 
                    : (keyBtn.isToggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2)
            }
        }
    }

    // Backspace key with auto-repeat
    component BackspaceBtn: RippleButton {
        id: bsBtn
        signal bsTriggered()

        implicitHeight: 40
        Layout.fillWidth: true
        buttonRadius: Appearance.rounding.small
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover

        Timer {
            id: repeatTimer
            interval: 70
            repeat: true
            onTriggered: bsBtn.bsTriggered()
        }
        Timer {
            id: delayTimer
            interval: 380
            onTriggered: repeatTimer.start()
        }

        onPressed: {
            bsBtn.bsTriggered();
            delayTimer.start();
        }
        onReleased: {
            delayTimer.stop();
            repeatTimer.stop();
        }
        onCanceled: {
            delayTimer.stop();
            repeatTimer.stop();
        }

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            iconSize: 20
            text: "backspace"
            color: Appearance.colors.colOnLayer2
        }
    }
}
