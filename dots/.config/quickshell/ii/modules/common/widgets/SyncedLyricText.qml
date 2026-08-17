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

    readonly property real ghostSpacing: 48
    readonly property real textWidth: marqueeText.implicitWidth
    readonly property bool overflow: textWidth > width + 1
    readonly property real unit: textWidth + ghostSpacing
    readonly property bool canKaraoke: overflow && !isInterlude && LyricSync.hasTiming(words, lineStartMs, lineEndMs)
    property real scrollX: 0
    property bool marqueeRunning: false
    property var charXs: []

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

    function applyKaraokeScroll() {
        if (!canKaraoke)
            return;
        var pos = LyricSync.nowPosition(playing, anchorPos, anchorAt, positionMs);
        var frac = LyricSync.playheadCharFrac(words, pos, lineStartMs, lineEndMs, marqueeText.text.length);
        var minX = Math.min(0, width - textWidth);
        var x = width * 0.42 - LyricSync.playheadX(charXs, frac);
        if (x > 0) x = 0;
        if (x < minX) x = minX;
        root.scrollX = x;
    }

    function restartScroll() {
        scrollAnim.stop();
        rebuildCharXs();
        if (isInterlude || !overflow) {
            marqueeRunning = false;
            root.scrollX = overflow ? 0 : (width - textWidth) / 2;
            return;
        }
        if (canKaraoke) {
            marqueeRunning = false;
            applyKaraokeScroll();
            return;
        }
        root.scrollX = 0;
        scrollAnim.duration = Math.max(800, unit * 25);
        marqueeRunning = true;
        scrollAnim.restart();
    }

    onWidthChanged: {
        if (canKaraoke)
            applyKaraokeScroll();
        else
            restartScroll();
    }
    onCanKaraokeChanged: restartScroll()
    onIsInterludeChanged: restartScroll()
    onPlayingChanged: {
        if (canKaraoke)
            applyKaraokeScroll();
    }
    onWordsChanged: {
        if (canKaraoke)
            applyKaraokeScroll();
    }

    FrameAnimation {
        running: root.canKaraoke && root.playing
        onTriggered: root.applyKaraokeScroll()
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
        renderType: Text.QtRendering
        text: root.isInterlude ? "" : root.text
        x: root.scrollX
        onTextChanged: root.restartScroll()
    }

    StyledText {
        id: ghostText
        anchors.verticalCenter: parent.verticalCenter
        width: implicitWidth
        elide: Text.ElideNone
        horizontalAlignment: Text.AlignLeft
        color: Appearance.colors.colOnLayer1
        renderType: Text.QtRendering
        text: root.isInterlude ? "" : root.text
        visible: root.marqueeRunning
        x: root.scrollX + root.unit
    }

    Row {
        id: interludeRow
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 4
        visible: root.isInterlude
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
