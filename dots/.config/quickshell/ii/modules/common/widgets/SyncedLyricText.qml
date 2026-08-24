import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick

// Clipped lyric / title label.
// If `words` has timings and the line overflows, scroll follows the playhead
// (karaoke). Otherwise a looping marquee, or centered when it fits.
Item {
    id: root
    clip: true
    implicitHeight: marqueeText.implicitHeight

    property string text: ""
    property var words: []
    property int lineStartMs: 0
    property int lineEndMs: 0
    property bool playing: false
    property int anchorPos: 0
    property real anchorAt: 0
    property int positionMs: 0
    property bool isInterlude: false
    // Short lyric gaps retain the last line. Freeze its position rather than
    // continuing to scroll with an already-finished timing range.
    property bool holdLine: false
    property string renderedText: ""
    property bool renderedInterlude: false

    readonly property real ghostSpacing: 48
    readonly property real textWidth: marqueeText.implicitWidth
    readonly property bool overflow: textWidth > width + 1
    readonly property real unit: textWidth + ghostSpacing
    readonly property bool hasTimedLyrics: !renderedInterlude && !holdLine && LyricSync.hasTiming(words, lineStartMs, lineEndMs)
    readonly property bool showWordHighlight: Config.options.media.wordHighlight && hasTimedLyrics
    readonly property bool canKaraoke: overflow && hasTimedLyrics
    property real scrollX: 0
    property bool marqueeRunning: false
    property var charXs: []
    property real karaokeProgressX: 0
    property int karaokeTargetIndex: -2
    property int lastKaraokePosition: -1
    property bool lineTransitionReady: false

    function rebuildCharXs() {
        var text = marqueeText.text;
        var xs = [0];
        if (text.length > 0) {
            for (var i = 1; i <= text.length; i++) {
                playheadMetrics.text = text.substring(0, i);
                xs.push(playheadMetrics.width);
            }
        }
        charXs = xs;
    }

    function syncKaraokeScroll() {
        if (!canKaraoke)
            return;
        var minX = Math.min(0, width - textWidth);
        var x = width * 0.5 - karaokeProgressX;
        if (x > 0) x = 0;
        if (x < minX) x = minX;
        root.scrollX = x;
    }

    function characterOffsetBeforeWord(index) {
        var offset = 0;
        for (var i = 0; i < index && i < words.length; i++)
            offset += (words[i].word || "").length;
        return offset;
    }

    // Lyricon advances the highlight once per word and lets the renderer
    // interpolate it for that word's remaining duration.  Do the same here:
    // the clock merely starts the next animation; it never writes scrollX on
    // every frame, which avoids visible polling corrections.
    function scheduleKaraoke() {
        if (!hasTimedLyrics || holdLine || !playing)
            return;
        var pos = LyricSync.nowPosition(playing, anchorPos, anchorAt, positionMs);
        var frac = LyricSync.playheadCharFrac(words, pos, lineStartMs, lineEndMs, marqueeText.text.length);
        if (pos < lineStartMs) {
            karaokeAnim.stop();
            karaokeProgressX = 0;
            karaokeTargetIndex = -2;
            lastKaraokePosition = pos;
            karaokeBoundaryTimer.interval = Math.max(16, lineStartMs - pos);
            karaokeBoundaryTimer.restart();
            return;
        }
        if (pos < lastKaraokePosition) {
            karaokeAnim.stop();
            karaokeProgressX = LyricSync.playheadX(charXs, frac);
            karaokeTargetIndex = -2;
        }
        lastKaraokePosition = pos;

        var wordIndex = -1;
        if (LyricSync.wordTimingsDistinct(words)) {
            for (var i = 0; i < words.length; i++) {
                var start = words[i].startTime ?? lineStartMs;
                var end = words[i].endTime ?? start;
                if (pos < end || i === words.length - 1) {
                    wordIndex = i;
                    break;
                }
            }
        }

        var targetFrac;
        var endMs;
        if (wordIndex >= 0) {
            targetFrac = wordIndex === words.length - 1
                ? marqueeText.text.length
                : characterOffsetBeforeWord(wordIndex) + (words[wordIndex].word || "").length;
            endMs = words[wordIndex].endTime ?? lineEndMs;
        } else {
            targetFrac = marqueeText.text.length;
            endMs = lineEndMs;
        }
        var targetX = LyricSync.playheadX(charXs, targetFrac);
        if (wordIndex === karaokeTargetIndex) {
            if (karaokeAnim.running || karaokeProgressX >= targetX - 0.5)
                return;
        }
        karaokeTargetIndex = wordIndex;
        karaokeAnim.stop();
        karaokeAnim.from = karaokeProgressX;
        karaokeAnim.to = targetX;
        karaokeAnim.duration = Math.max(1, endMs - pos);
        karaokeAnim.restart();
        karaokeBoundaryTimer.interval = Math.max(16, endMs - pos + 8);
        karaokeBoundaryTimer.restart();
    }

    function seekKaraoke() {
        var pos = LyricSync.nowPosition(playing, anchorPos, anchorAt, positionMs);
        var frac = LyricSync.playheadCharFrac(words, pos, lineStartMs, lineEndMs, marqueeText.text.length);
        karaokeAnim.stop();
        karaokeProgressX = LyricSync.playheadX(charXs, frac);
        karaokeTargetIndex = -2;
        lastKaraokePosition = pos;
        syncKaraokeScroll();
        scheduleKaraoke();
    }

    function restartScroll() {
        scrollAnim.stop();
        karaokeAnim.stop();
        karaokeBoundaryTimer.stop();
        rebuildCharXs();
        karaokeTargetIndex = -2;
        lastKaraokePosition = -1;
        if (renderedInterlude || !overflow) {
            marqueeRunning = false;
            root.scrollX = overflow ? 0 : (width - textWidth) / 2;
            if (hasTimedLyrics)
                seekKaraoke();
            return;
        }
        if (holdLine) {
            marqueeRunning = false;
            return;
        }
        if (canKaraoke) {
            marqueeRunning = false;
            seekKaraoke();
            return;
        }
        root.scrollX = 0;
        scrollAnim.duration = Math.max(800, unit * 25);
        marqueeRunning = true;
        scrollAnim.restart();
    }

    onWidthChanged: {
        if (canKaraoke)
            seekKaraoke();
        else
            restartScroll();
    }
    onCanKaraokeChanged: restartScroll()
    onHasTimedLyricsChanged: restartScroll()
    onIsInterludeChanged: requestLineChange()
    onHoldLineChanged: restartScroll()
    onPlayingChanged: {
        if (!playing) {
            karaokeAnim.stop();
            karaokeBoundaryTimer.stop();
        } else if (hasTimedLyrics) {
            seekKaraoke();
        }
    }
    onWordsChanged: {
        if (hasTimedLyrics)
            seekKaraoke();
    }

    Timer {
        id: karaokeBoundaryTimer
        repeat: false
        onTriggered: root.scheduleKaraoke()
    }

    // The main timer only fires at word boundaries.  This inexpensive guard
    // recovers if an animation is cancelled by a transient layout/source
    // update before that boundary callback gets a chance to run.
    Timer {
        interval: 120
        repeat: true
        running: root.hasTimedLyrics && root.playing
        onTriggered: root.scheduleKaraoke()
    }

    NumberAnimation {
        id: karaokeAnim
        target: root
        property: "karaokeProgressX"
        easing.type: Easing.Linear
    }

    function requestLineChange() {
        if (text === renderedText && isInterlude === renderedInterlude)
            return;
        if (!lineTransitionReady) {
            renderedText = text;
            renderedInterlude = isInterlude;
            return;
        }
        lineChangeAnim.stop();
        lineChangeAnim.restart();
    }

    onTextChanged: requestLineChange()
    onRenderedTextChanged: restartScroll()

    Component.onCompleted: {
        renderedText = text;
        renderedInterlude = isInterlude;
        lineTransitionReady = true;
    }

    SequentialAnimation {
        id: lineChangeAnim
        NumberAnimation {
            target: root
            property: "opacity"
            to: 0
            duration: 80
            easing.type: Easing.InCubic
        }
        ScriptAction {
            script: {
                root.renderedText = root.text;
                root.renderedInterlude = root.isInterlude;
            }
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 1
                duration: 180
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "scale"
                from: 0.985
                to: 1
                duration: 180
                easing.type: Easing.OutCubic
            }
        }
    }

    TextMetrics {
        id: playheadMetrics
        font: marqueeText.font
    }

    StyledText {
        id: marqueeText
        anchors.verticalCenter: parent.verticalCenter
        width: implicitWidth
        elide: Text.ElideNone
        horizontalAlignment: Text.AlignLeft
        color: Appearance.colors.colOnLayer1
        opacity: root.showWordHighlight ? 0.5 : 1
        renderType: Text.QtRendering
        text: root.renderedInterlude ? "" : root.renderedText
        x: root.scrollX
    }

    Item {
        x: root.scrollX
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(root.textWidth, root.karaokeProgressX)
        height: marqueeText.implicitHeight
        clip: true
        visible: root.showWordHighlight && !root.renderedInterlude

        StyledText {
            width: implicitWidth
            elide: Text.ElideNone
            horizontalAlignment: Text.AlignLeft
            color: Appearance.colors.colPrimary
            renderType: Text.QtRendering
            text: root.renderedText
        }
    }

    onKaraokeProgressXChanged: syncKaraokeScroll()

    StyledText {
        id: ghostText
        anchors.verticalCenter: parent.verticalCenter
        width: implicitWidth
        elide: Text.ElideNone
        horizontalAlignment: Text.AlignLeft
        color: Appearance.colors.colOnLayer1
        renderType: Text.QtRendering
        text: root.renderedInterlude ? "" : root.renderedText
        visible: root.marqueeRunning
        x: root.scrollX + root.unit
    }

    Row {
        id: interludeRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        visible: root.renderedInterlude
        MaterialSymbol {
            text: "music_note"
            iconSize: Appearance.font.pixelSize.small
            fill: 1
            color: Appearance.colors.colOnLayer1
        }
        MaterialSymbol {
            text: "music_note"
            iconSize: Appearance.font.pixelSize.small
            fill: 1
            color: Appearance.colors.colOnLayer1
        }
        MaterialSymbol {
            text: "music_note"
            iconSize: Appearance.font.pixelSize.small
            fill: 1
            color: Appearance.colors.colOnLayer1
        }
    }

    NumberAnimation {
        id: scrollAnim
        target: root
        property: "scrollX"
        from: 0
        to: -root.unit
        loops: Animation.Infinite
        running: false
        easing.type: Easing.Linear
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 14
        visible: root.overflow && root.scrollX < -0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "black" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        opacity: 0.35
    }
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 14
        visible: root.overflow && root.scrollX + root.textWidth > root.width + 0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: "black" }
        }
        opacity: 0.35
    }
}
