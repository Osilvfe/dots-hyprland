import QtQuick
import Quickshell.Hyprland
import qs.services
import qs.modules.common as C

NestableObject {
    id: root

    required property HyprlandMonitor monitor
    readonly property var liveMonitorData: HyprlandData.monitors.find(m => m.id === monitor?.id)
    readonly property int activeWorkspace: monitor?.activeWorkspace?.id ?? 1
    readonly property var activeWorkspaceData: HyprlandData.workspaceById[activeWorkspace]
    readonly property bool currentWorkspaceNotFake: (activeWorkspaceData?.windows ?? 0) > 0
    readonly property int fakeWorkspace: currentWorkspaceNotFake ? -9999 : activeWorkspace
    readonly property int shownCount: C.Config.options.bar.workspaces.shown
    readonly property int group: Math.floor((activeWorkspace - 1) / shownCount)
    readonly property var specialWorkspace: liveMonitorData?.specialWorkspace
    readonly property string specialWorkspaceName: specialWorkspace?.name?.replace("special:", "") ?? "special"
    readonly property bool specialWorkspaceActive: specialWorkspaceName !== ""

    property list<bool> occupied: []
    property list<var> biggestWindow: {
        const windows = HyprlandData.windowList;
        return occupied.map((_, index) => {
            const wsId = getWorkspaceIdAt(index);
            const workspaceWindows = windows.filter(window => window.workspace.id === wsId);
            return workspaceWindows.reduce((largest, window) => {
                const largestArea = (largest?.size?.[0] ?? 0) * (largest?.size?.[1] ?? 0);
                const windowArea = (window?.size?.[0] ?? 0) * (window?.size?.[1] ?? 0);
                return windowArea > largestArea ? window : largest;
            }, null);
        });
    }

    function getWorkspaceId(group, index) {
        return group * root.shownCount + index + 1;
    }
    function getWorkspaceIdAt(index) {
        return root.getWorkspaceId(root.group, index);
    }

    // Function to update workspaceOccupied
    function updateWorkspaceOccupied() {
        root.occupied = Array.from({
            length: root.shownCount
        }, (_, i) => {
            const thisWorkspaceId = getWorkspaceId(root.group, i);
            return Hyprland.workspaces.values.some(ws => ws.id === thisWorkspaceId);
        });
    }

    // Occupied workspace updates
    Component.onCompleted: updateWorkspaceOccupied()
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            root.updateWorkspaceOccupied();
        }
    }
    onGroupChanged: {
        updateWorkspaceOccupied();
    }
}
