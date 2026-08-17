pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import qs.services
import qs.modules.common.functions

// Facade over lyric backends. The bar binds to this, never to a specific player.
//
// Source contract (duck-typed QtObject / Singleton):
//   ready: bool                 // false while unreachable (optional; default true)
//   lineText: string            // current line; empty = no synced line
//   isInterlude: bool           // instrumental gap (bar shows notes, not text)
//   lineWords: var              // [{word, startTime, endTime}] milliseconds
//   lineStartMs, lineEndMs: int
//   positionMs: int
//   playing: bool
//   anchorPos: int              // last sampled position
//   anchorAt: real              // Date.now() of that sample (for local clock)
//   title, artist: string       // optional now-playing metadata
//
// To add a backend: implement the contract, then insert it in `active` below
// (first match wins).
Singleton {
    id: root

    readonly property var active: {
        if (SPlayer.ready !== false && (SPlayer.lineText.length > 0 || SPlayer.title.length > 0))
            return SPlayer;
        return null;
    }

    readonly property bool available: !!active
    readonly property string lineText: active?.lineText ?? ""
    readonly property bool isInterlude: !!(active?.isInterlude)
    readonly property var lineWords: active?.lineWords ?? []
    readonly property int lineStartMs: active?.lineStartMs ?? 0
    readonly property int lineEndMs: active?.lineEndMs ?? 0
    readonly property int positionMs: active?.positionMs ?? 0
    readonly property bool playing: !!(active?.playing)
    readonly property int anchorPos: active?.anchorPos ?? 0
    readonly property real anchorAt: active?.anchorAt ?? 0
    readonly property string title: active?.title ?? ""
    readonly property string artist: active?.artist ?? ""

    readonly property bool hasSyncedLine: lineText.length > 0 && !isInterlude
    readonly property bool hasWordTiming: LyricSync.hasTiming(lineWords, lineStartMs, lineEndMs)
    readonly property string trackLabel: title
        ? (artist ? `${title} • ${artist}` : title)
        : ""

    function nowPosition() {
        return LyricSync.nowPosition(playing, anchorPos, anchorAt, positionMs);
    }
}
