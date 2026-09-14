pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

Singleton {
    id: root

    readonly property PolkitAgent agent: polkitAgentLoader.item
    readonly property bool active: agent?.isActive ?? false
    readonly property var flow: agent?.flow ?? null
    readonly property bool isRegistered: agent?.isRegistered ?? false
    property bool interactionAvailable: false
    property int retryCount: 0

    function init() {
        return root.isRegistered;
    }

    property string cleanMessage: {
        if (!root.flow) return "";
        return root.flow.message.endsWith(".")
            ? root.flow.message.slice(0, -1)
            : root.flow.message;
    }
    property string cleanPrompt: {
        const inputPrompt = root.flow?.inputPrompt.trim() ?? "";
        const cleanedInputPrompt = inputPrompt.endsWith(":") ? inputPrompt.slice(0, -1) : inputPrompt;
        const usePasswordChars = !root.flow?.responseVisible ?? true;
        return cleanedInputPrompt || (usePasswordChars ? Translation.tr("Password") : Translation.tr("Input"));
    }

    function cancel() {
        if (root.flow) {
            root.flow.cancelAuthenticationRequest();
        }
    }

    function submit(string) {
        if (root.flow) {
            root.flow.submit(string);
        }
        root.interactionAvailable = false;
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            root.interactionAvailable = true;
        }
    }

    Timer {
        id: retryTimer
        interval: root.retryCount < 5 ? 1500 : 5000
        repeat: true
        running: polkitAgentLoader.item && !polkitAgentLoader.item.isRegistered && root.retryCount < 30
        onTriggered: {
            root.retryCount++;
            console.log(`[PolkitService] Authentication agent not registered (attempt ${root.retryCount}), retrying...`);
            polkitAgentLoader.active = false;
            reloadTimer.start();
        }
    }

    Timer {
        id: reloadTimer
        interval: 200
        repeat: false
        onTriggered: {
            polkitAgentLoader.active = true;
        }
    }

    Loader {
        id: polkitAgentLoader
        active: true
        sourceComponent: Component {
            PolkitAgent {
                id: innerAgent
                onAuthenticationRequestStarted: {
                    root.interactionAvailable = true;
                }
                onIsRegisteredChanged: {
                    if (innerAgent.isRegistered) {
                        root.retryCount = 0;
                        console.log("[PolkitService] Successfully registered with PolicyKit");
                    }
                }
            }
        }
    }
}
