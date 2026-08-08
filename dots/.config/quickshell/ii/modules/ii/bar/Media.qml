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

        // Marquee text: scrolls when the line is too wide, else centered
        Item {
            id: textClip
            Layout.fillWidth: true
            Layout.rightMargin: rowLayout.spacing
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: true
            clip: true

            readonly property real scrollDistance: Math.max(0, marqueeText.implicitWidth - width)
            property real scrollX: 0
            property bool scrolling: false

            function restartScroll() {
                scrollAnim.stop()
                if (textClip.scrollDistance > 0) {
                    scrollOut.duration = Math.max(1200, textClip.scrollDistance * 25)
                    scrollBack.duration = Math.max(1200, textClip.scrollDistance * 25)
                    textClip.scrollX = 0
                    textClip.scrolling = true
                    scrollAnim.restart()
                } else {
                    textClip.scrolling = false
                    textClip.scrollX = (width - marqueeText.implicitWidth) / 2
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
                text: root.displayText
                x: textClip.scrollX
                onTextChanged: textClip.restartScroll()
            }

            SequentialAnimation {
                id: scrollAnim
                loops: Animation.Infinite
                running: false
                NumberAnimation {
                    id: scrollOut
                    target: textClip
                    property: "scrollX"
                    to: -textClip.scrollDistance
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 900 }
                NumberAnimation {
                    id: scrollBack
                    target: textClip
                    property: "scrollX"
                    to: 0
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 900 }
            }
        }

    }

}
