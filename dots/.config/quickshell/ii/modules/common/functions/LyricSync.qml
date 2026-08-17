pragma Singleton
import Quickshell

// Source-agnostic helpers for timed lyrics.
// Word objects: { word: string, startTime: number, endTime: number }  (ms)
Singleton {
    id: root

    function joinWords(words) {
        if (!words || words.length === 0)
            return "";
        var text = "";
        for (var i = 0; i < words.length; i++)
            text += words[i].word || "";
        return text;
    }

    function nowPosition(playing, anchorPos, anchorAt, fallbackPos) {
        if (playing && anchorAt)
            return anchorPos + (Date.now() - anchorAt);
        return fallbackPos || 0;
    }

    function hasTiming(words, startTime, endTime) {
        if ((endTime || 0) > (startTime || 0))
            return true;
        if (!words || words.length === 0)
            return false;
        for (var i = 0; i < words.length; i++) {
            if ((words[i].endTime || 0) > (words[i].startTime || 0))
                return true;
            if (i > 0 && words[i].startTime !== words[0].startTime)
                return true;
        }
        return false;
    }

    function wordTimingsDistinct(words) {
        if (!words || words.length <= 1)
            return false;
        var first = words[0].startTime;
        for (var i = 1; i < words.length; i++) {
            if (words[i].startTime !== first)
                return true;
        }
        return false;
    }

    // Pixel X of a (possibly fractional) character offset into precomputed prefix widths.
    function playheadX(charXs, frac) {
        if (!charXs || charXs.length === 0)
            return 0;
        var last = charXs.length - 1;
        if (frac <= 0)
            return charXs[0];
        if (frac >= last)
            return charXs[last];
        var i0 = Math.floor(frac);
        var x0 = charXs[i0];
        return x0 + (charXs[i0 + 1] - x0) * (frac - i0);
    }

    // Character offset (can be fractional) of the playhead in `textLength`.
    // Uses per-word times when they differ; otherwise interpolates the whole line.
    function playheadCharFrac(words, pos, startTime, endTime, textLength) {
        var n = textLength || 0;
        if (n <= 0)
            return 0;
        var a = startTime || 0;
        var b = endTime || 0;
        if (!wordTimingsDistinct(words)) {
            if (!(b > a) && words && words.length === 1) {
                a = words[0].startTime ?? a;
                b = words[0].endTime ?? b;
            }
            if (!(b > a))
                return 0;
            var p = (pos - a) / (b - a);
            if (p < 0) p = 0;
            if (p > 1) p = 1;
            return p * n;
        }
        var charOffset = 0;
        for (var i = 0; i < words.length; i++) {
            var w = words[i];
            var len = (w.word || "").length;
            if (len <= 0)
                continue;
            var start = w.startTime ?? a;
            var end = w.endTime ?? start;
            if (pos < start)
                return charOffset;
            var last = (i === words.length - 1);
            if (pos < end || last) {
                var wp = 1;
                if (end > start)
                    wp = (pos - start) / (end - start);
                if (wp < 0) wp = 0;
                if (wp > 1) wp = 1;
                return charOffset + wp * len;
            }
            charOffset += len;
        }
        return n;
    }
}
