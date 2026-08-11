import QtQuick
import QtWebSockets

// SPlayer-Next external API WebSocket client.
// Must be a standalone component whose ROOT type is WebSocket:
//   - a WebSocket declared inside a Singleton (or as a child QtObject) never
//     connects under quickshell/qml_rs, so it is created via createComponent.
//   - creating it with createObject(null) and forwarding events from its own
//     signal handlers (not external .connect()) is the only reliable pattern.
WebSocket {
    id: ws
    url: "ws://127.0.0.1:14558/ws"
    active: true

    onStatusChanged: (status) => SPlayer.onWsStatus(status)
    onTextMessageReceived: (message) => SPlayer.onWsMessage(String(message))
}
