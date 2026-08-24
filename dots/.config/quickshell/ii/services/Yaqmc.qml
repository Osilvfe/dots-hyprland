pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// YAQMC local HTTP API lyric source (https://github.com/Osilvfe/YAQMC).
// Enable "Local HTTP API" in YAQMC on 127.0.0.1:19532.  The API token is
// intentionally opt-in here; leave it empty when YAQMC's local API has no
// bearer token, or set it locally if one is configured in YAQMC.
Singleton {
    id: root

    readonly property string apiBase: "http://127.0.0.1:19532/v1"
    property string apiToken: ""
    readonly property int httpTimeoutMs: 3000
    readonly property int pollIntervalMs: 500
    readonly property int backoffMinMs: 3000
    readonly property int backoffMaxMs: 30000

    // Implements the Lyrics source contract (see services/Lyrics.qml).
    readonly property bool ready: !apiDown
    property bool apiDown: false
    property string trackId: ""
    property string title: ""
    property string artist: ""
    property string lineText: ""
    property bool isInterlude: false
    property bool holdLine: false
    property var lineWords: []
    property var lyricLines: []
    property int lineStartMs: 0
    property int lineEndMs: 0
    property int positionMs: 0
    property int durationMs: 0
    property int minInterludeGap: 4000
    property int lineTransitionLeadMs: 260
    property bool playing: false
    property int anchorPos: 0
    property double anchorAt: 0
    property int failBackoffMs: backoffMinMs
    property bool playerRequestInFlight: false
    property bool lyricRequestInFlight: false
    property bool lyricDocumentRequestInFlight: false
    property int playerRequestId: 0
    property double playerRequestStartedAt: 0
    property int previewLineStartMs: -1
    property string previewTrackId: ""

    function request(path, onDone, onFail) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", `${root.apiBase}${path}`);
        xhr.timeout = root.httpTimeoutMs;
        if (root.apiToken)
            xhr.setRequestHeader("Authorization", `Bearer ${root.apiToken}`);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status === 200) {
                try {
                    onDone(JSON.parse(xhr.responseText));
                } catch (error) {
                    console.error(`[Yaqmc] parse error: ${error.message}`);
                    if (onFail)
                        onFail();
                }
            } else if (onFail) {
                onFail();
            }
        };
        xhr.onerror = function() {
            if (onFail)
                onFail();
        };
        xhr.ontimeout = function() {
            if (onFail)
                onFail();
        };
        xhr.send();
    }

    function setAnchor(position, sampledAt) {
        var elapsed = sampledAt ? Math.max(0, Math.min(1000, Date.now() - Number(sampledAt))) : 0;
        root.anchorPos = Math.max(0, (Number(position) || 0) + elapsed);
        root.positionMs = root.anchorPos;
        root.anchorAt = Date.now();
    }

    function markApiUp() {
        root.apiDown = false;
        root.failBackoffMs = root.backoffMinMs;
    }

    function clearAll() {
        cancelLinePreview();
        root.trackId = "";
        root.title = "";
        root.artist = "";
        root.lineText = "";
        root.lineWords = [];
        root.lyricLines = [];
        root.lineStartMs = 0;
        root.lineEndMs = 0;
        root.isInterlude = false;
        root.holdLine = false;
        root.positionMs = 0;
        root.durationMs = 0;
        root.playing = false;
        root.anchorPos = 0;
        root.anchorAt = 0;
    }

    function cancelLinePreview() {
        previewTimer.stop();
        root.previewLineStartMs = -1;
        root.previewTrackId = "";
    }

    function handleApiDown() {
        root.apiDown = true;
        // A dropped YAQMC process can leave an XMLHttpRequest pending until
        // its callback arrives. Do not let that stale request block probes of
        // the freshly restarted local API.
        root.playerRequestId++;
        root.playerRequestInFlight = false;
        root.lyricRequestInFlight = false;
        root.lyricDocumentRequestInFlight = false;
        root.clearAll();
        root.failBackoffMs = Math.min(root.failBackoffMs * 2, root.backoffMaxMs);
    }

    function applyPlayer(snapshot) {
        root.markApiUp();
        var index = snapshot?.currentIndex;
        var track = index === null || index === undefined ? null : snapshot?.queue?.[index];
        if (!track) {
            root.clearAll();
            return;
        }
        var nextTrackId = track.id || "";
        if (nextTrackId !== root.trackId) {
            root.cancelLinePreview();
            root.trackId = nextTrackId;
            root.lineText = "";
            root.lineWords = [];
            root.lineStartMs = 0;
            root.lineEndMs = 0;
            root.isInterlude = false;
            root.holdLine = false;
            root.lyricLines = [];
            root.loadLyrics();
        }
        root.title = track.title || "";
        root.artist = (track.artists || []).map((value) => value?.name || "").filter((value) => value).join("/");
        root.durationMs = Number(snapshot.playbackDurationMs ?? track.durationMs ?? 0) || 0;
        root.playing = snapshot.isPlaying === true;
        root.setAnchor(snapshot.positionMs, snapshot.sampledAtMs);
    }

    function applyCurrentLyric(current) {
        root.markApiUp();
        if (!root.trackId || current?.songId !== root.trackId)
            return;
        // Once the full document is present, local time is authoritative for
        // line changes.  Waiting for this 500 ms-polled endpoint makes the
        // display visibly late and can overwrite a scheduled gap transition.
        if (root.lyricLines.length > 0)
            return;
        var line = current.line;
        if (!line) {
            var position = Number(current.positionMs) || root.positionMs;
            // A long enough lyric gap is used to replace the next line just
            // before it starts, so the bar's out/in transition happens in the
            // silence rather than after the new lyric has begun.
            if (root.previewLineStartMs > position)
                return;
            if (!root.inInterlude(position)) {
                // YAQMC correctly reports no *active* line during a short
                // gap. Keep the previous lyric visible, matching the existing
                // SPlayer source, instead of falling back to the track title.
                var previousLine = root.latestLineAtOrBefore(position);
                if (previousLine) {
                    root.applyLine(previousLine);
                    root.holdLine = true;
                    return;
                }
                // Keep the currently rendered line even while the full lyric
                // document is still loading.  `/lyrics/current` deliberately
                // returns null between lines, which must never expose the
                // track-title fallback for a normal short gap.
                if (root.lineText.length > 0 && !root.isInterlude) {
                    root.holdLine = true;
                    return;
                }
            }
            root.lineText = "";
            root.lineWords = [];
            root.lineStartMs = 0;
            root.lineEndMs = 0;
            root.isInterlude = root.inInterlude(position);
            root.holdLine = false;
            return;
        }
        if (root.previewLineStartMs < 0
                && Number(line.startMs) === root.lineStartMs
                && (line.text || "") === root.lineText) {
            root.holdLine = false;
            return;
        }
        root.cancelLinePreview();
        root.holdLine = false;
        root.applyLine(line);
    }

    function applyLine(line, isPreview) {
        root.lineText = line.text || "";
        root.lineWords = (line.words || []).map((word) => ({
            "word": word.text || "",
            "startTime": Number(word.startMs) || 0,
            "endTime": Number(word.endMs) || 0
        }));
        root.lineStartMs = Number(line.startMs) || 0;
        root.lineEndMs = Number(line.endMs) || 0;
        root.isInterlude = false;
        root.holdLine = false;
        if (!isPreview)
            root.scheduleNextLinePreview(line);
    }

    function nextLineAfter(line) {
        var start = Number(line?.startMs);
        if (!isFinite(start))
            return null;
        for (var index = 0; index < root.lyricLines.length; index++) {
            var candidate = root.lyricLines[index];
            if (Number(candidate.startMs) > start)
                return candidate;
        }
        return null;
    }

    function lineAtStart(startMs) {
        for (var index = 0; index < root.lyricLines.length; index++) {
            var line = root.lyricLines[index];
            if (Number(line.startMs) === startMs)
                return line;
        }
        return null;
    }

    function refreshCachedLyric() {
        if (!root.playing || root.lyricLines.length === 0)
            return;
        var position = root.anchorAt
            ? root.anchorPos + (Date.now() - root.anchorAt)
            : root.positionMs;

        // Keep the preloaded next line intact while its transition is running
        // inside the gap before that line actually starts.
        if (root.previewLineStartMs > position)
            return;

        if (root.inInterlude(position)) {
            if (!root.isInterlude) {
                root.lineText = "";
                root.lineWords = [];
                root.lineStartMs = 0;
                root.lineEndMs = 0;
                root.isInterlude = true;
                root.holdLine = false;
            }
            return;
        }

        var line = root.latestLineAtOrBefore(position);
        if (!line)
            return;
        var start = Number(line.startMs) || 0;
        var end = Number(line.endMs) || start;
        if (start === root.lineStartMs && (line.text || "") === root.lineText) {
            if (root.previewLineStartMs >= 0)
                root.cancelLinePreview();
            root.holdLine = position > end;
            return;
        }
        root.cancelLinePreview();
        root.applyLine(line);
    }

    function scheduleNextLinePreview(line) {
        root.cancelLinePreview();
        if (!root.playing || !line)
            return;
        var next = root.nextLineAfter(line);
        var end = Number(line.endMs);
        var nextStart = Number(next?.startMs);
        if (!next || !isFinite(end) || !isFinite(nextStart)
                || nextStart - end < root.lineTransitionLeadMs)
            return;
        var now = root.anchorAt ? root.anchorPos + (Date.now() - root.anchorAt) : root.positionMs;
        var delay = nextStart - now - root.lineTransitionLeadMs;
        if (delay <= 0)
            return;
        root.previewLineStartMs = nextStart;
        root.previewTrackId = root.trackId;
        previewTimer.interval = Math.max(1, delay);
        previewTimer.restart();
    }

    function latestLineAtOrBefore(position) {
        var result = null;
        for (var index = 0; index < root.lyricLines.length; index++) {
            var line = root.lyricLines[index];
            var start = Number(line.startMs);
            if (isFinite(start) && start <= position)
                result = line;
            else if (isFinite(start))
                break;
        }
        return result;
    }

    // Match SPlayer's presentation rule: only a deliberate, long lyric gap is
    // an interlude. Short timing gaps should remain quiet instead of showing
    // the music-note indicator.
    function inInterlude(position) {
        if (root.lyricLines.length === 0)
            return false;
        var pos = Number(position);
        if (!isFinite(pos))
            pos = root.positionMs;
        var previousEnd = 0;
        for (var index = 0; index < root.lyricLines.length; index++) {
            var line = root.lyricLines[index];
            var start = Number(line.startMs);
            if (!isFinite(start))
                continue;
            var gapStart = previousEnd;
            var gapEnd = Math.max(gapStart, start - 250);
            if (gapEnd - gapStart >= root.minInterludeGap && pos > gapStart && pos < gapEnd)
                return true;

            var end = Number(line.endMs);
            if (!isFinite(end)) {
                for (var next = index + 1; next < root.lyricLines.length; next++) {
                    var nextStart = Number(root.lyricLines[next].startMs);
                    if (isFinite(nextStart)) {
                        end = nextStart;
                        break;
                    }
                }
            }
            previousEnd = Math.max(previousEnd, isFinite(end) ? end : start);
        }
        return root.durationMs - previousEnd >= root.minInterludeGap && pos > previousEnd && pos < root.durationMs;
    }

    function loadLyrics() {
        if (root.lyricDocumentRequestInFlight)
            return;
        var requestedTrackId = root.trackId;
        root.lyricDocumentRequestInFlight = true;
        root.request("/lyrics", function(document) {
            root.lyricDocumentRequestInFlight = false;
            root.markApiUp();
            if (requestedTrackId !== root.trackId)
                return;
            root.lyricLines = document?.songId === requestedTrackId && Array.isArray(document?.lines) ? document.lines : [];
            var activeLine = root.latestLineAtOrBefore(root.positionMs);
            if (activeLine && Number(activeLine.startMs) === root.lineStartMs)
                root.scheduleNextLinePreview(activeLine);
            if (!root.lineText)
                root.isInterlude = root.inInterlude(root.positionMs);
        }, function() {
            root.lyricDocumentRequestInFlight = false;
        });
    }

    function refreshPlayer() {
        if (root.playerRequestInFlight)
            return;
        root.playerRequestInFlight = true;
        root.playerRequestStartedAt = Date.now();
        var requestId = ++root.playerRequestId;
        root.request("/player", function(snapshot) {
            if (requestId !== root.playerRequestId)
                return;
            root.playerRequestInFlight = false;
            root.applyPlayer(snapshot);
        }, function() {
            if (requestId !== root.playerRequestId)
                return;
            root.playerRequestInFlight = false;
            root.handleApiDown();
        });
    }

    function refreshCurrentLyric() {
        if (root.lyricRequestInFlight || root.apiDown)
            return;
        root.lyricRequestInFlight = true;
        root.request("/lyrics/current", function(current) {
            root.lyricRequestInFlight = false;
            root.applyCurrentLyric(current);
        }, function() {
            root.lyricRequestInFlight = false;
        });
    }

    Timer {
        id: previewTimer
        repeat: false
        onTriggered: {
            if (!root.playing || root.previewTrackId !== root.trackId)
                return;
            var next = root.lineAtStart(root.previewLineStartMs);
            var now = root.anchorAt ? root.anchorPos + (Date.now() - root.anchorAt) : root.positionMs;
            if (next && now < root.previewLineStartMs)
                root.applyLine(next, true);
        }
    }

    Timer {
        // The player endpoint only calibrates the clock.  Resolve lyric lines
        // from that clock locally so a new line is shown within one frame-ish
        // tick rather than one network polling interval later.
        interval: 80
        running: root.playing && root.lyricLines.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshCachedLyric()
    }

    Timer {
        interval: root.apiDown ? root.failBackoffMs : root.pollIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refreshPlayer();
            root.refreshCurrentLyric();
        }
    }

    // XMLHttpRequest normally honors `timeout`, but a local process dying
    // while its socket is being established has occasionally left the request
    // pending. This guarantees the reconnect loop continues.
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            if (root.playerRequestInFlight && Date.now() - root.playerRequestStartedAt > root.httpTimeoutMs + 1000)
                root.handleApiDown();
        }
    }
}
