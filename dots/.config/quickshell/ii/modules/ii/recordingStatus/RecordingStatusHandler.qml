pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs

Scope {
    id: root

    IpcHandler {
        target: "recording"

        function status(type: string): void {
            if (type === "none") {
                GlobalStates.recordingType = "none";
                return;
            }
            if (GlobalStates.recordingType === "none") {
                GlobalStates.recordingStartedAt = Date.now();
            }
            GlobalStates.recordingType = type;
        }
    }
}
