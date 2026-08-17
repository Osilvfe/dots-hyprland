pragma Singleton
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs
import qs.modules.common.functions

/**
 * Clash Verge Rev.
 * Tile state is read from Mihomo HTTP (secret/controller from clash-verge.yaml).
 * On/off clicks Clash Verge's own tray menu (SystemTray + QsMenuOpener) so the
 * GUI runs patch_verge + refresh_verge.
 */
Singleton {
    id: root

    readonly property string vergeDir: FileUtils.trimFileProtocol(`${StandardPaths.standardLocations(StandardPaths.GenericDataLocation)[0]}/io.github.clash-verge-rev.clash-verge-rev`)
    readonly property string defaultHost: "127.0.0.1"
    readonly property int defaultMixedPort: 7897
    readonly property string defaultController: "127.0.0.1:9097"
    readonly property var tunLabels: ["TUN 模式", "TUN Mode"]
    readonly property var sysproxyLabels: ["系统代理", "System Proxy"]

    property bool available: false
    property bool running: false
    property bool systemProxy: false
    property bool tun: false
    property string secret: ""
    property string proxyHost: defaultHost
    property int mixedPort: defaultMixedPort
    property string controller: defaultController
    property bool pendingTunOn: false
    property var trayQueue: []
    property string pendingTrayKind: ""
    property bool pendingTrayOn: false
    property int trayTries: 0
    property int waitTries: 0
    readonly property string apiBase: `http://${root.controller}`
    readonly property string authHeader: root.secret !== "" ? `Authorization: Bearer ${root.secret}` : ""
    readonly property bool active: systemProxy || tun
    readonly property string statusText: {
        if (systemProxy && tun)
            return Translation.tr("System proxy + TUN");
        if (tun)
            return Translation.tr("TUN");
        if (systemProxy)
            return Translation.tr("System proxy");
        return Translation.tr("Off");
    }

    function yamlValue(text, key) {
        const match = text.match(new RegExp(`^${key}:\\s*(.*)$`, "m"));
        if (!match)
            return "";
        return match[1].trim().replace(/^['"]|['"]$/g, "");
    }

    function patchYamlBool(text, key, value) {
        const line = `${key}: ${value ? "true" : "false"}`;
        const re = new RegExp(`^${key}:.*$`, "m");
        if (re.test(text))
            return text.replace(re, line);
        return (text.endsWith("\n") ? text : text + "\n") + line + "\n";
    }

    function parseVergeYaml(text) {
        const host = root.yamlValue(text, "proxy_host");
        if (host)
            root.proxyHost = host;
        const port = parseInt(root.yamlValue(text, "verge_mixed_port"));
        if (!isNaN(port) && port > 0)
            root.mixedPort = port;
    }

    function parseClashYaml(text) {
        const secret = root.yamlValue(text, "secret");
        root.secret = secret;
        const ext = root.yamlValue(text, "external-controller");
        if (ext && ext.indexOf(":") >= 0)
            root.controller = ext;
        else
            root.controller = root.defaultController;
    }

    function patchVergeYaml(key, value) {
        let text = "";
        try {
            text = vergeFileView.text();
        } catch (e) {
            return;
        }
        if (!text)
            return;
        const next = root.patchYamlBool(text, key, value);
        if (next !== text)
            vergeFileView.setText(next);
    }

    function refresh() {
        if (root.secret === "")
            return;
        runningProc.running = true;
        proxyProc.running = true;
        tunProc.running = true;
    }

    function refreshSoon() {
        refreshSoonTimer.restart();
    }

    function ensureRunning() {
        if (root.running)
            return;
        Quickshell.execDetached(["clash-verge"]);
    }

    function findVergeTray() {
        const items = SystemTray.items.values;
        for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const hay = `${item.id} ${item.title} ${item.tooltipTitle}`.toLowerCase();
            if (hay.indexOf("clash") >= 0 || hay.indexOf("verge") >= 0)
                return item;
        }
        return null;
    }

    function bindVergeMenu() {
        const item = root.findVergeTray();
        if (!item || !item.hasMenu)
            return false;
        if (vergeMenuOpener.menu !== item.menu)
            vergeMenuOpener.menu = item.menu;
        return true;
    }

    function findTrayEntry(labels) {
        const children = vergeMenuOpener.children.values;
        for (let i = 0; i < children.length; i++) {
            const entry = children[i];
            if (labels.indexOf(entry.text) >= 0)
                return entry;
        }
        return null;
    }

    function tryTrayClick() {
        if (root.pendingTrayKind === "")
            return false;
        const labels = root.pendingTrayKind === "tun" ? root.tunLabels : root.sysproxyLabels;
        const entry = root.findTrayEntry(labels);
        if (!entry)
            return false;
        const checked = entry.checkState === Qt.Checked;
        if (checked !== root.pendingTrayOn)
            entry.triggered();
        root.finishTray(true);
        return true;
    }

    function finishTray(ok) {
        trayWaitTimer.stop();
        if (!ok) {
            if (root.pendingTrayKind === "tun")
                root.applyTunFallback(root.pendingTrayOn);
            else if (root.pendingTrayKind === "sysproxy")
                root.applySystemProxyFallback(root.pendingTrayOn);
        }
        root.pendingTrayKind = "";
        root.refreshSoon();
        if (root.trayQueue.length === 0)
            return;
        const job = root.trayQueue[0];
        root.trayQueue = root.trayQueue.slice(1);
        root.startTray(job.kind, job.on);
    }

    function startTray(kind, on) {
        root.pendingTrayKind = kind;
        root.pendingTrayOn = on;
        root.trayTries = 0;
        root.bindVergeMenu();
        if (root.tryTrayClick())
            return;
        trayWaitTimer.restart();
    }

    function enqueueTray(kind, on) {
        if (root.pendingTrayKind !== "") {
            root.trayQueue = root.trayQueue.concat([{
                kind: kind,
                on: on
            }]);
            return;
        }
        root.startTray(kind, on);
    }

    function applySystemProxyFallback(on) {
        if (on) {
            const host = root.proxyHost;
            const port = root.mixedPort;
            Quickshell.execDetached(["bash", "-c",
                `gsettings set org.gnome.system.proxy.http host '${host}' && ` +
                `gsettings set org.gnome.system.proxy.http port ${port} && ` +
                `gsettings set org.gnome.system.proxy.https host '${host}' && ` +
                `gsettings set org.gnome.system.proxy.https port ${port} && ` +
                `gsettings set org.gnome.system.proxy.socks host '${host}' && ` +
                `gsettings set org.gnome.system.proxy.socks port ${port} && ` +
                `gsettings set org.gnome.system.proxy mode manual`
            ]);
        } else {
            Quickshell.execDetached(["gsettings", "set", "org.gnome.system.proxy", "mode", "none"]);
        }
        root.patchVergeYaml("enable_system_proxy", on);
    }

    function applyTunFallback(on) {
        if (root.secret === "")
            return;
        Quickshell.execDetached([
            "curl", "-sS",
            "-H", root.authHeader,
            "-H", "Content-Type: application/json",
            "-X", "PATCH", `${root.apiBase}/configs`,
            "-d", `{"tun":{"enable":${on}}}`
        ]);
        root.patchVergeYaml("enable_tun_mode", on);
    }

    function applySystemProxy(on) {
        root.enqueueTray("sysproxy", on);
    }

    function applyTun(on) {
        root.enqueueTray("tun", on);
    }

    function waitForCoreThenTun() {
        root.waitTries = 0;
        waitApiProc.running = true;
        waitForCoreTimer.restart();
    }

    function setSystemProxy(on) {
        root.systemProxy = on;
        if (on)
            root.ensureRunning();
        root.applySystemProxy(on);
        root.refreshSoon();
    }

    function setTun(on) {
        root.tun = on;
        if (on && !root.running) {
            root.pendingTunOn = true;
            root.ensureRunning();
            root.waitForCoreThenTun();
            return;
        }
        root.pendingTunOn = false;
        waitForCoreTimer.stop();
        root.applyTun(on);
        root.refreshSoon();
    }

    function disconnectAll() {
        root.pendingTunOn = false;
        waitForCoreTimer.stop();
        root.systemProxy = false;
        root.tun = false;
        root.applySystemProxy(false);
        root.applyTun(false);
        root.refreshSoon();
    }

    function toggle() {
        if (root.active)
            root.disconnectAll();
        else
            root.setTun(true);
    }

    function openApp() {
        Quickshell.execDetached(["clash-verge"]);
        GlobalStates.sidebarRightOpen = false;
    }

    QsMenuOpener {
        id: vergeMenuOpener
        onChildrenChanged: root.tryTrayClick()
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshSoonTimer
        interval: 800
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: trayWaitTimer
        interval: 200
        repeat: true
        onTriggered: {
            root.trayTries += 1;
            root.bindVergeMenu();
            if (root.tryTrayClick())
                return;
            if (root.trayTries > 20)
                root.finishTray(false);
        }
    }

    Timer {
        id: waitForCoreTimer
        interval: 250
        repeat: true
        onTriggered: {
            root.waitTries += 1;
            if (root.waitTries > 32) {
                stop();
                root.waitTries = 0;
                if (root.pendingTunOn)
                    root.applyTun(true);
                root.pendingTunOn = false;
                root.refreshSoon();
                return;
            }
            waitApiProc.running = true;
        }
    }

    FileView {
        id: vergeFileView
        path: `${root.vergeDir}/verge.yaml`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseVergeYaml(text())
    }

    FileView {
        id: clashFileView
        path: `${root.vergeDir}/clash-verge.yaml`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.parseClashYaml(text());
            root.refresh();
        }
    }

    Process {
        id: availabilityProc
        running: true
        command: ["bash", "-c", "command -v clash-verge >/dev/null 2>&1"]
        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0;
        }
    }

    Process {
        id: runningProc
        command: ["curl", "-sf", "-H", root.authHeader, `${root.apiBase}/version`]
        onExited: (exitCode, exitStatus) => {
            root.running = exitCode === 0;
        }
    }

    Process {
        id: waitApiProc
        command: ["curl", "-sf", "-H", root.authHeader, `${root.apiBase}/version`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                return;
            waitForCoreTimer.stop();
            root.waitTries = 0;
            root.running = true;
            if (root.pendingTunOn)
                root.applyTun(true);
            root.pendingTunOn = false;
            root.refreshSoon();
        }
    }

    Process {
        id: proxyProc
        command: ["gsettings", "get", "org.gnome.system.proxy", "mode"]
        stdout: StdioCollector {
            id: proxyOut
            onStreamFinished: {
                const mode = proxyOut.text.trim().replace(/'/g, "");
                if (mode === "manual" || mode === "none")
                    root.systemProxy = mode === "manual";
            }
        }
    }

    Process {
        id: tunProc
        command: ["curl", "-sS", "-H", root.authHeader, `${root.apiBase}/configs`]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !root.running)
                root.tun = false;
        }
        stdout: StdioCollector {
            id: tunOut
            onStreamFinished: {
                const text = tunOut.text.trim();
                if (!text.startsWith("{"))
                    return;
                try {
                    const data = JSON.parse(text);
                    root.tun = !!(data.tun && data.tun.enable);
                } catch (e) {
                }
            }
        }
    }
}
