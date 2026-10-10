pragma Singleton
import Quickshell
import qs.services
import qs.modules.common

Singleton {
    id: root

    function closeAllWindows() {
        HyprlandData.windowList.map(w => w.pid).forEach(pid => {
            Quickshell.execDetached(["kill", pid]);
        });
    }

    function changePassword() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.changePassword}`]);
    }

    function lock() {
        Quickshell.execDetached(["loginctl", "lock-session"]);
    }

    function suspend() {
        Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"]);
    }

    function handleSessionExit(systemCmd) {
        const shouldSave = Config.options.session?.restoreWindowsOnLogin ?? true;
        const script = Directories.sessionRestoreScriptPath;
        const saveArg = shouldSave ? "save" : "clear";
        const fullCmd = `python3 "${script}" ${saveArg}; ${systemCmd}`;
        Quickshell.execDetached(["bash", "-c", fullCmd]);
    }

    function logout() {
        handleSessionExit("pkill -i Hyprland");
    }

    function launchTaskManager() {
        Quickshell.execDetached(["bash", "-c", `${Config.options.apps.taskManager}`]);
    }

    function hibernate() {
        Quickshell.execDetached(["bash", "-c", `systemctl hibernate || loginctl hibernate`]);
    }

    function poweroff() {
        handleSessionExit("systemctl poweroff || loginctl poweroff");
    }

    function reboot() {
        handleSessionExit("reboot || loginctl reboot");
    }

    function rebootToFirmware() {
        handleSessionExit("systemctl reboot --firmware-setup || loginctl reboot --firmware-setup");
    }
}
