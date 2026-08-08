pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// SPlayer-Next external HTTP API integration
// (https://github.com/SPlayer-Dev/SPlayer-Next, external API server)
// Provides now-playing title/artist and synced lyric line for the bar media widget.
Singleton {
    id: root

    readonly property string apiBase: "http://127.0.0.1:14558/api"

    // current line text (synced), or empty when no lyrics / no player
    property string lineText: ""
    property string title: ""
    property string artist: ""
    property bool lyricAvailable: false

    property var lyricLines: []
    property int positionMs: 0

    function httpGet(url, onDone) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try { onDone(JSON.parse(xhr.responseText)) }
                    catch (e) { console.error(`[SPlayer] parse error: ${e.message}`) }
                }
            }
        }
        xhr.send()
    }

    // Fetch now-playing once per track change; caches lyrics for that track.
    property string loadedTrackId: ""

    function refreshNowPlaying() {
        root.httpGet(`${root.apiBase}/now-playing`, function(np) {
            if (!np?.track) {
                root.title = ""
                root.artist = ""
                root.lyricAvailable = false
                root.lyricLines = []
                root.lineText = ""
                return
            }
            root.title = np.track.title ?? ""
            root.artist = np.track.artists?.map(a => a.name).join("/") ?? ""
            root.lyricAvailable = !!np.lyricAvailable
            if (np.track.id !== root.loadedTrackId) {
                root.loadedTrackId = np.track.id
                root.loadLyrics()
            }
        })
    }

    function loadLyrics() {
        root.httpGet(`${root.apiBase}/lyrics`, function(res) {
            root.lyricLines = Array.isArray(res?.lyric) ? res.lyric : []
            root.updateLine()
        })
    }

    function updateLine() {
        if (root.lyricLines.length === 0) { root.lineText = ""; return }
        var pos = root.positionMs
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

    // Poll /api/status for position (cheap), and refresh now-playing periodically
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            root.httpGet(`${root.apiBase}/status`, function(st) {
                root.positionMs = st.position ?? 0
                root.updateLine()
            })
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: root.refreshNowPlaying()
    }

    Component.onCompleted: root.refreshNowPlaying()
}
