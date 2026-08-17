pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtWebSockets

// SPlayer-Next external API integration
// (https://github.com/SPlayer-Dev/SPlayer-Next, external API server)
// Provides now-playing title/artist and synced lyric line for the bar media widget.
// Primary channel is the WebSocket (/ws): the server pushes track/lyric/status
// events. It does NOT push continuous position (HIGH_FREQ_EVENTS filter), so we
// extrapolate position from the last status anchor with a local clock, and keep
// a low-frequency HTTP /api/status poll as a calibration/failure fallback.
// If the WebSocket is unavailable (only HTTP enabled), we degrade to plain HTTP
// polling (old behavior) driven by the same status timer.
//
// NOTE: a WebSocket declared inside a Singleton (or as a child QtObject) never
// connects under quickshell/qml_rs. It is therefore created dynamically via
// createComponent from wsclient.qml (root type WebSocket, events forwarded to
// the SPlayer singleton from its own signal handlers).
Singleton {
    id: root

    readonly property string apiBase: "http://127.0.0.1:14558/api"
    readonly property string wsUrl: "ws://127.0.0.1:14558/ws"
    readonly property int httpTimeoutMs: 3000
    readonly property int statusPollWhenWsMs: 8000
    readonly property int backoffMinMs: 3000
    readonly property int backoffMaxMs: 30000

    // current line text (synced), or empty when no lyrics / no player
    property string lineText: ""
    property string title: ""
    property string artist: ""
    property bool lyricAvailable: false

    property var lyricLines: []
    property int positionMs: 0
    // track duration (ms), used to detect a long instrumental outro after the
    // last lyric line
    property int durationMs: 0
    // true when the SPlayer API is unreachable (app closed); clears everything
    property bool apiDown: false

    // text shown in the bar while inside an instrumental gap (interlude/intro)
    property string interludeText: "♪ ♪ ♪"
    // minimum gap (ms) between lyric lines that counts as an interlude
    property int minInterludeGap: 4000

    // local-clock position extrapolation anchor (set by any status event/poll)
    property int anchorPos: 0
    property double anchorAt: 0
    property bool playing: false

    // dynamically created WebSocket (see NOTE above)
    property var socket: null
    property bool wsConnected: false

    property int failBackoffMs: 3000
    property double lastBackoffAt: 0

    function httpGet(url, onDone, onFail) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.timeout = root.httpTimeoutMs
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try { onDone(JSON.parse(xhr.responseText)) }
                    catch (e) { console.error(`[SPlayer] parse error: ${e.message}`) }
                } else if (onFail) {
                    onFail()
                }
            }
        }
        xhr.onerror = function() {
            if (onFail) onFail()
        }
        xhr.ontimeout = function() {
            if (onFail) onFail()
        }
        xhr.send()
    }

    function markApiUp() {
        root.apiDown = false
        root.failBackoffMs = root.backoffMinMs
        root.lastBackoffAt = 0
    }

    function clearAll() {
        root.title = ""
        root.artist = ""
        root.lyricAvailable = false
        root.lyricLines = []
        root.lineText = ""
        root.loadedTrackId = ""
        root.playing = false
        root.durationMs = 0
        root.positionMs = 0
        root.anchorPos = 0
        root.anchorAt = 0
    }

    function handleApiDown() {
        if (!root.apiDown) {
            root.apiDown = true
            root.clearAll()
        }
        if (Date.now() - root.lastBackoffAt > 2000) {
            root.lastBackoffAt = Date.now()
            root.failBackoffMs = Math.min(root.failBackoffMs * 2, root.backoffMaxMs)
        }
    }

    // Fetch now-playing once per track change; caches lyrics for that track.
    property string loadedTrackId: ""

    function refreshNowPlaying() {
        root.httpGet(`${root.apiBase}/now-playing`, function(np) {
            root.markApiUp()
            if (!np?.track) {
                root.clearAll()
                return
            }
            root.title = np.track.title ?? ""
            root.artist = np.track.artists?.map(a => a.name).join("/") ?? ""
            root.lyricAvailable = !!np.lyricAvailable
            if (np.track.id !== root.loadedTrackId) {
                root.loadedTrackId = np.track.id
                root.durationMs = 0
                root.loadLyrics()
            }
        }, root.handleApiDown)
    }

    function loadLyrics() {
        root.httpGet(`${root.apiBase}/lyrics`, function(res) {
            root.markApiUp()
            root.lyricLines = Array.isArray(res?.lyric) ? res.lyric : []
            root.lyricAvailable = root.lyricLines.length > 0
            root.updateLine()
        }, root.handleApiDown)
    }

    function setAnchor(pos) {
        root.anchorPos = pos
        root.anchorAt = Date.now()
        root.positionMs = pos
    }

    function refreshStatus() {
        root.httpGet(`${root.apiBase}/status`, function(st) {
            root.markApiUp()
            root.playing = st.state === "playing"
            if (st.duration) root.durationMs = st.duration
            root.setAnchor(st.position ?? 0)
            root.updateLine()
        }, root.handleApiDown)
    }

    // Mirror SPlayer's detectInterlude: when the position is inside a gap of
    // >= minInterludeGap between lyric lines (or before the first line), we are
    // in an intro/interlude instrumental section. Extended: a long gap after
    // the last lyric line (up to track end) is also an instrumental outro.
    function inInterlude(pos) {
        var lines = root.lyricLines
        if (lines.length === 0) return false
        var t = pos + 20
        // candidate gap = between line[i-1].endTime and line[i].startTime-250
        for (var i = 0; i < lines.length; i++) {
            var gapStart = i === 0 ? 0 : (lines[i - 1].endTime ?? 0)
            var gapEnd = Math.max(gapStart, (lines[i].startTime ?? 0) - 250)
            if (gapEnd - gapStart < root.minInterludeGap) continue
            if (t > gapStart && t < gapEnd) return true
        }
        // outro: after the last lyric line until the track ends
        if (root.durationMs > 0) {
            var lastEnd = lines[lines.length - 1].endTime ?? 0
            var outroEnd = Math.max(lastEnd, root.durationMs)
            if (outroEnd - lastEnd >= root.minInterludeGap && t > lastEnd && t < outroEnd) return true
        }
        return false
    }

    function updateLine() {
        if (root.apiDown || root.lyricLines.length === 0) { root.lineText = ""; return }
        var pos = root.positionMs
        if (root.inInterlude(pos)) {
            if (root.lineText !== root.interludeText) root.lineText = root.interludeText
            return
        }
        var active = ""
        for (var i = 0; i < root.lyricLines.length; i++) {
            var line = root.lyricLines[i]
            if (line.isBG) continue
            if (pos >= (line.startTime ?? 0) - 100) {
                var words = line.words || []
                active = words.map(w => w.word).join("")
            } else {
                break
            }
        }
        if (root.lineText !== active) root.lineText = active
    }

    // ---- WebSocket (primary channel) ----
    function connectWs() {
        if (root.socket) {
            root.socket.active = false
            root.socket.destroy()
            root.socket = null
        }
        var comp = Qt.createComponent("wsclient.qml")
        if (comp.status !== Component.Ready) {
            console.error("[SPlayer] wsclient.qml compile error:", comp.errorString())
            reconnectTimer.restart()
            return
        }
        root.socket = comp.createObject(null)
        if (!root.socket) {
            console.error("[SPlayer] failed to create WebSocket")
            reconnectTimer.restart()
        }
    }

    function onWsStatus(status) {
        if (status === WebSocket.Open) {
            root.wsConnected = true
            root.markApiUp()
            reconnectTimer.stop()
            // server only sends hello on connect; pull current state once
            root.refreshNowPlaying()
            root.refreshStatus()
        } else if (status === WebSocket.Error || status === WebSocket.Closed) {
            root.wsConnected = false
            // WS down (SPlayer exited, or WS not enabled) - HTTP fallback
            // will confirm whether the API itself is gone.
            reconnectTimer.restart()
        }
    }

    function onWsMessage(message) {
        var msg
        try { msg = JSON.parse(message) } catch (e) { return }
        if (msg.kind === "hello") return
        if (msg.kind !== "event") return
        switch (msg.type) {
        case "track": {
            root.markApiUp()
            var t = msg.data?.track ?? null
            if (!t) { root.clearAll(); return }
            root.title = t.title ?? ""
            root.artist = (t.artists || []).map(a => a.name).join("/") ?? ""
            root.lyricAvailable = false
            root.durationMs = 0
            if (t.id !== root.loadedTrackId) {
                root.loadedTrackId = t.id
                root.lyricLines = []
                root.lineText = ""
                // lyric event usually follows; HTTP fetch as fallback
                root.loadLyrics()
            }
            break
        }
        case "lyric": {
            root.markApiUp()
            root.lyricLines = Array.isArray(msg.data?.lyric) ? msg.data.lyric : []
            root.lyricAvailable = root.lyricLines.length > 0
            root.updateLine()
            break
        }
        case "status": {
            root.markApiUp()
            var st = msg.data ?? {}
            root.playing = st.state === "playing"
            if (st.duration) root.durationMs = st.duration
            root.setAnchor(st.position ?? root.positionMs)
            root.updateLine()
            break
        }
        case "ended":
            root.playing = false
            break
        }
    }

    // Retry the WebSocket when it drops (SPlayer restarting, etc.)
    Timer {
        id: reconnectTimer
        interval: root.failBackoffMs
        repeat: true
        onTriggered: {
            if (root.wsConnected) {
                reconnectTimer.stop()
                return
            }
            root.connectWs()
        }
    }

    // Local-clock extrapolation while playing (WS does not push position).
    // Re-anchored by every status event / status poll.
    Timer {
        interval: 200
        running: root.playing
        repeat: true
        onTriggered: {
            root.positionMs = root.anchorPos + Math.round(Date.now() - root.anchorAt)
            root.updateLine()
        }
    }

    // HTTP status poll: calibrates the local clock while WS is up, and is the
    // now-playing/failure probe when WS is down. Backs off while the API is gone.
    Timer {
        interval: root.wsConnected ? root.statusPollWhenWsMs : root.failBackoffMs
        running: true
        repeat: true
        onTriggered: {
            root.refreshStatus()
            if (!root.wsConnected)
                root.refreshNowPlaying()
        }
    }

    Component.onCompleted: {
        // prime the state immediately; WS connect will refresh anyway
        root.refreshNowPlaying()
        root.refreshStatus()
        root.connectWs()
    }
}
