pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int shiftMode: 0 // 0: off, 1: one shot, 2: locked
    readonly property list<int> shiftKeys: [42, 54]
    readonly property list<int> altKeys: [56, 100]
    readonly property list<int> ctrlKeys: [29, 97]
    property bool ctrlActive: false
    property bool altActive: false
    property bool altGrActive: false
    property var pendingCommands: []

    readonly property var specialKeyNames: ({
        1: "Escape",
        14: "BackSpace",
        15: "Tab",
        28: "Return",
        57: "space",
        59: "F1",
        60: "F2",
        61: "F3",
        62: "F4",
        63: "F5",
        64: "F6",
        65: "F7",
        66: "F8",
        67: "F9",
        68: "F10",
        87: "F11",
        88: "F12",
        99: "Print",
        105: "Left",
        106: "Right",
        111: "Delete",
        139: "Menu"
    })

    readonly property var shortcutKeyNames: ({
        2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0",
        12: "minus", 13: "equal",
        16: "q", 17: "w", 18: "e", 19: "r", 20: "t", 21: "y", 22: "u", 23: "i", 24: "o", 25: "p",
        26: "bracketleft", 27: "bracketright",
        30: "a", 31: "s", 32: "d", 33: "f", 34: "g", 35: "h", 36: "j", 37: "k", 38: "l",
        39: "semicolon", 40: "apostrophe", 41: "grave", 43: "backslash",
        44: "z", 45: "x", 46: "c", 47: "v", 48: "b", 49: "n", 50: "m",
        51: "comma", 52: "period", 53: "slash", 57: "space", 86: "less"
    })

    function isModifierActive(keycode: int): bool {
        if (root.shiftKeys.includes(keycode)) return root.shiftMode !== 0;
        if (root.ctrlKeys.includes(keycode)) return root.ctrlActive;
        if (keycode === 100) return root.altGrActive;
        if (keycode === 56) return root.altActive;
        return false;
    }

    function modifierArguments(includeShift: bool): var {
        const args = [];
        if (includeShift && root.shiftMode !== 0) args.push("-M", "shift");
        if (root.ctrlActive) args.push("-M", "ctrl");
        if (root.altActive) args.push("-M", "alt");
        if (root.altGrActive) args.push("-M", "altgr");
        return args;
    }

    function enqueue(command: var): void {
        root.pendingCommands = root.pendingCommands.concat([command]);
        root.runNext();
    }

    function runNext(): void {
        if (keyProcess.running || root.pendingCommands.length === 0) return;
        keyProcess.command = root.pendingCommands[0];
        keyProcess.running = true;
    }

    function releaseAllKeys(): void {
        root.shiftMode = 0;
        root.ctrlActive = false;
        root.altActive = false;
        root.altGrActive = false;
    }

    function releaseShiftKeys(): void {
        root.shiftMode = 0;
    }

    function press(keycode: int, text: string): void {
        if (root.shiftKeys.includes(keycode)) return;
        if (root.ctrlKeys.includes(keycode)) {
            root.ctrlActive = true;
            return;
        }
        if (keycode === 56) {
            root.altActive = true;
            return;
        }
        if (keycode === 100) {
            root.altGrActive = true;
            return;
        }

        const specialName = root.specialKeyNames[keycode];
        if (specialName !== undefined) {
            root.enqueue(["wtype", ...root.modifierArguments(true), "-k", specialName]);
            return;
        }

        // Shortcut modifiers need a physical key name. Plain text goes through
        // wtype's Unicode path so all OSK layouts work independently of XKB.
        if (root.ctrlActive || root.altActive || (root.altGrActive && text.length === 0)) {
            const shortcutName = root.shortcutKeyNames[keycode];
            if (shortcutName !== undefined) {
                root.enqueue(["wtype", ...root.modifierArguments(true), "-k", shortcutName]);
            }
            return;
        }
        if (text.length > 0) root.enqueue(["wtype", text]);
    }

    function release(keycode: int): void {
        if (root.shiftKeys.includes(keycode)) {
            root.releaseShiftKeys();
        } else if (root.ctrlKeys.includes(keycode)) {
            root.ctrlActive = false;
        } else if (keycode === 56) {
            root.altActive = false;
        } else if (keycode === 100) {
            root.altGrActive = false;
        }
    }

    Process {
        id: keyProcess
        onExited: {
            root.pendingCommands = root.pendingCommands.slice(1);
            Qt.callLater(root.runNext);
        }
    }
}
