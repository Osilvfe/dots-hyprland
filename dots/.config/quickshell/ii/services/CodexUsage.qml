pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Reads the current account's Codex quota through the locally authenticated
 * Codex app-server. The helper prints only the rate-limit response and never
 * exposes or reads account credentials itself.
 */
Singleton {
    id: root

    property bool available: false
    property bool refreshing: false
    property string planType: ""
    property int primaryUsedPercent: 0
    property int primaryWindowMinutes: 0
    property double primaryResetsAt: 0
    property int secondaryUsedPercent: 0
    property int secondaryWindowMinutes: 0
    property double secondaryResetsAt: 0
    property double lastUpdated: 0
    // The local mixed port is usable before the asynchronous running-state
    // probe finishes, which avoids an initial direct request on proxy-only
    // networks.
    readonly property bool useClashProxy: ClashVerge.proxyHost.length > 0 && ClashVerge.mixedPort > 0
    readonly property string clashProxyUrl: `http://${ClashVerge.proxyHost}:${ClashVerge.mixedPort}`

    readonly property bool hasPrimary: available && primaryWindowMinutes > 0
    readonly property bool hasSecondary: available && secondaryWindowMinutes > 0
    readonly property int primaryRemainingPercent: Math.max(0, 100 - primaryUsedPercent)
    readonly property int secondaryRemainingPercent: Math.max(0, 100 - secondaryUsedPercent)

    function setWindow(prefix, source) {
        if (!source || typeof source.usedPercent !== "number")
            return false;

        const used = Math.max(0, Math.min(100, Math.round(source.usedPercent)));
        const minutes = typeof source.windowDurationMins === "number" ? Math.max(0, Math.round(source.windowDurationMins)) : 0;
        const resetsAt = typeof source.resetsAt === "number" ? source.resetsAt : 0;

        if (prefix === "primary") {
            primaryUsedPercent = used;
            primaryWindowMinutes = minutes;
            primaryResetsAt = resetsAt;
        } else {
            secondaryUsedPercent = used;
            secondaryWindowMinutes = minutes;
            secondaryResetsAt = resetsAt;
        }
        return minutes > 0;
    }

    function applyResponse(text) {
        try {
            const message = JSON.parse(text.trim());
            const snapshot = message?.result?.rateLimits;
            if (!snapshot || typeof snapshot !== "object")
                return false;

            const primaryOk = setWindow("primary", snapshot.primary);
            const secondaryOk = setWindow("secondary", snapshot.secondary);
            planType = snapshot.planType ?? "";
            available = primaryOk || secondaryOk;
            if (available)
                lastUpdated = Date.now();
            return available;
        } catch (error) {
            return false;
        }
    }

    function refresh() {
        if (refreshing || !(Config.options.bar.indicators.showCodexUsage ?? true))
            return;
        refreshing = true;
        usageProcess.running = true;
    }

    function windowLabel(minutes) {
        if (minutes <= 0)
            return "";
        if (Math.abs(minutes - 300) <= 30)
            return "5h";
        if (Math.abs(minutes - 1440) <= 144)
            return Translation.tr("Daily");
        if (Math.abs(minutes - 10080) <= 1008)
            return Translation.tr("Weekly");
        if (Math.abs(minutes - 43200) <= 4320)
            return Translation.tr("Monthly");
        return `${minutes}m`;
    }

    function resetText(epochSeconds) {
        const seconds = Math.max(0, Math.floor(epochSeconds - Date.now() / 1000));
        if (seconds <= 0)
            return Translation.tr("Now");
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        if (days > 0)
            return `${days}d ${hours}h`;
        if (hours > 0)
            return `${hours}h ${minutes}m`;
        return `${minutes}m`;
    }

    Process {
        id: usageProcess
        command: root.useClashProxy
            ? ["env", `http_proxy=${root.clashProxyUrl}`, `https_proxy=${root.clashProxyUrl}`, `all_proxy=${root.clashProxyUrl}`, "bash", `${Directories.scriptPath}/codex-usage.sh`]
            : ["bash", `${Directories.scriptPath}/codex-usage.sh`]
        stdout: StdioCollector {
            id: usageOutput
            onStreamFinished: {
                if (!root.applyResponse(text))
                    console.warn("[CodexUsage] Could not parse the rate-limit response");
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.refreshing = false;
            if (exitCode !== 0)
                console.warn(`[CodexUsage] Query exited with code ${exitCode}`);
        }
    }

    Timer {
        interval: 300000
        running: Config.options.bar.indicators.showCodexUsage ?? true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Connections {
        target: ClashVerge
        function onRunningChanged() {
            if (ClashVerge.running)
                root.refresh();
        }
    }

    IpcHandler {
        target: "codexUsage"

        function refresh(): void {
            root.refresh();
        }

        function status(): void {
            console.log(`[CodexUsage] available=${root.available}, primary=${root.primaryUsedPercent}, secondary=${root.secondaryUsedPercent}, refreshing=${root.refreshing}, proxy=${root.useClashProxy} (${root.clashProxyUrl})`);
        }
    }
}
