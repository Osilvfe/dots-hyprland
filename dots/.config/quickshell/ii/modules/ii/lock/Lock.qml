pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root

    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})

    function defaultWorkspaceForMonitor(monName: string): int {
        return monName === "eDP-1" ? 11 : 1;
    }

    function sanitizeWorkspaceId(id: int, monName: string): int {
        if (id > 2000000 && id < 2147483647) {
            const restored = 2147483647 - id;
            if (restored >= 1 && restored <= 100) return restored;
        }
        if (id >= 1 && id <= 100) return id;
        return defaultWorkspaceForMonitor(monName);
    }

    function doRestoreWorkspaces() {
        if (!(Config.options.lock.slideWorkspaces ?? false)) return;
        var batch = "";
        for (var j = 0; j < Quickshell.screens.length; ++j) {
            var monName = Quickshell.screens[j].name;
            var targetWs = root.savedWorkspaces[monName];
            targetWs = sanitizeWorkspaceId(targetWs ?? -1, monName);
            batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${monName}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${targetWs}})'; `;
        }
        if (batch.length > 0) {
            Quickshell.execDetached(["bash", "-c", batch]);
        }
    }

    Timer {
        id: restoreTimer
        interval: 150
        repeat: false
        onTriggered: root.doRestoreWorkspaces()
    }

    Timer {
        id: restoreVerifyTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (GlobalStates.screenLocked) return;
            // 校验是否仍有显示器卡在临时超大工作区
            for (var i = 0; i < HyprlandData.monitors.length; ++i) {
                var mon = HyprlandData.monitors[i];
                var wsId = mon?.activeWorkspace?.id ?? 1;
                if (wsId > 2000000) {
                    var safeWs = sanitizeWorkspaceId(wsId, mon.name);
                    Quickshell.execDetached(["bash", "-c", `hyprctl dispatch 'hl.dsp.focus({monitor="${mon.name}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${safeWs}})';`]);
                }
            }
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                if (Config.options.lock.slideWorkspaces ?? false) {
                    var next = Object.assign({}, root.savedWorkspaces);
                    var batch = "keyword animation workspaces,1,7,menu_decel,slidevert; ";
                    for (var i = 0; i < Quickshell.screens.length; ++i) {
                        var mon = Quickshell.screens[i].name;
                        var mData = HyprlandData.monitors.find(m => m.name === mon);
                        var rawWs = mData?.activeWorkspace?.id;
                        var ws = sanitizeWorkspaceId(rawWs ?? root.savedWorkspaces[mon] ?? defaultWorkspaceForMonitor(mon), mon);
                        next[mon] = ws;
                        batch += `hyprctl dispatch 'hl.dsp.focus({monitor="${mon}"})'; hyprctl dispatch 'hl.dsp.focus({workspace=${2147483647 - ws}})'; `;
                    }
                    root.savedWorkspaces = next;
                    Quickshell.execDetached(["bash", "-c", batch]);
                }
            } else {
                root.doRestoreWorkspaces();
                restoreTimer.start();
                restoreVerifyTimer.start();
            }
        }
    }
}
