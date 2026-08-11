import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Hyprland

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")

    // SPlayer-Next lyric line, else title • artist
    readonly property string splayerTitle: SPlayer.title
    readonly property string splayerArtist: SPlayer.artist
    readonly property string displayText: SPlayer.lineText
        ? SPlayer.lineText
        : (splayerTitle
            ? `${splayerTitle}${splayerArtist ? ' • ' + splayerArtist : ''}`
            : `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`)

    readonly property bool isInterlude: SPlayer.lineText === SPlayer.interludeText
    readonly property int barHeight: Appearance.sizes.barHeight

    Layout.fillHeight: true
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: Appearance.sizes.barHeight

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                activePlayer.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                activePlayer.next();
            } else if (event.button === Qt.LeftButton) {
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }
    }

    RowLayout { // Real content
        id: rowLayout

        spacing: 4
        anchors.fill: parent

        ClippedFilledCircularProgress {
            id: mediaCircProg
            Layout.alignment: Qt.AlignVCenter
            lineWidth: Appearance.rounding.unsharpen
            value: activePlayer?.position / activePlayer?.length
            implicitSize: 20
            colPrimary: Appearance.colors.colOnSecondaryContainer
            enableAnimation: false

            Item {
                anchors.centerIn: parent
                width: mediaCircProg.implicitSize
                height: mediaCircProg.implicitSize
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        // Marquee text: seamless ghost scroll when the line is too wide, else centered
        Item {
            id: textClip
            Layout.fillWidth: true
            Layout.rightMargin: rowLayout.spacing
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: true
            clip: true

            readonly property real ghostSpacing: 48
            readonly property real textWidth: marqueeText.implicitWidth
            readonly property bool overflow: textWidth > width
            // Scrolls one full "text + gap" unit; the ghost copy makes it loop seamlessly
            readonly property real unit: textWidth + ghostSpacing
            property real scrollX: 0
            property bool scrolling: false

            function restartScroll() {
                scrollAnim.stop()
                textClip.scrollX = 0
                if (textClip.overflow) {
                    // constant speed (px/ms), like lyricon's ~40dp/s
                    scrollAnim.duration = Math.max(800, textClip.unit * 25)
                    textClip.scrolling = true
                    scrollAnim.restart()
                } else {
                    textClip.scrolling = false
                    textClip.scrollX = (width - textWidth) / 2
                }
            }

            onWidthChanged: textClip.restartScroll()

            StyledText {
                id: marqueeText
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                elide: Text.ElideNone
                horizontalAlignment: Text.AlignLeft
                color: Appearance.colors.colOnLayer1
                text: root.isInterlude ? "" : root.displayText
                x: textClip.scrollX
                onTextChanged: textClip.restartScroll()
            }

            StyledText {
                id: ghostText
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                elide: Text.ElideNone
                horizontalAlignment: Text.AlignLeft
                color: Appearance.colors.colOnLayer1
                text: root.isInterlude ? "" : root.displayText
                visible: textClip.scrolling
                x: textClip.scrollX + textClip.unit
            }

            // Interlude/instrumental indicator: render ♪ ♪ ♪ via the Material
            // icon font (the ♪ glyph falls back to a tiny symbol in the CJK
            // body font otherwise). Stated statically: Repeater delegates with
            // the icon font fail to render under quickshell.
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
                target: textClip
                property: "scrollX"
                from: 0
                to: -textClip.unit
                loops: Animation.Infinite
                running: false
                easing.type: Easing.Linear
            }

            // Fading edges (like lyricon's getLeft/RightFadingEdgeStrength):
            // semi-transparent gradients over the clipped content
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 14
                visible: textClip.scrolling
                gradient: Gradient {
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
                visible: textClip.scrolling
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: "black" }
                }
                opacity: 0.35
            }
        }

    }

}
