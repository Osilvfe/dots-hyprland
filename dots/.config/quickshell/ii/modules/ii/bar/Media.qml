import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property string mprisTrackLabel: activePlayer?.trackTitle
        ? `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`
        : ""
    readonly property bool hasMediaContent: Lyrics.hasSyncedLine
        || mprisTrackLabel.length > 0
        || Lyrics.trackLabel.length > 0

    readonly property string displayText: Lyrics.hasSyncedLine
        ? Lyrics.lineText
        : (mprisTrackLabel || Lyrics.trackLabel || Translation.tr("No media"))

    readonly property bool isInterlude: Lyrics.isInterlude

    function updateLyricPosition() {
        const item = (lyricText && lyricText.width > 0) ? lyricText : root;
        try {
            let pos = null;
            const targetCenterX = item.width > 0 ? (item.width / 2) : 0;
            if (root.QsWindow && typeof root.QsWindow.mapFromItem === "function") {
                pos = root.QsWindow.mapFromItem(item, targetCenterX, 0);
            } else if (typeof item.mapToItem === "function") {
                pos = item.mapToItem(null, targetCenterX, 0);
            }
            if (pos && typeof pos.x === "number" && !isNaN(pos.x)) {
                GlobalStates.mediaCenterX = pos.x;
                GlobalStates.mediaButtonScreen = root.QsWindow?.window?.screen ?? null;
            }
        } catch (e) {
            console.warn("Error updating media lyric position:", e);
        }
    }

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen && !GlobalStates.mediaButtonScreen) {
                const myScreen = root.QsWindow?.window?.screen;
                const focusedScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name);
                if (myScreen && focusedScreen && myScreen.name === focusedScreen.name) {
                    root.updateLyricPosition();
                }
            }
        }
    }

    Layout.fillHeight: true
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: Appearance.sizes.barHeight

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer?.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                activePlayer?.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer?.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                activePlayer?.next();
            } else if (event.button === Qt.LeftButton) {
                root.updateLyricPosition();
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen;
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

        SyncedLyricText {
            id: lyricText
            Layout.fillWidth: true
            Layout.rightMargin: rowLayout.spacing
            Layout.alignment: Qt.AlignVCenter
            Layout.fillHeight: true
            text: root.displayText
            animateContent: root.hasMediaContent
            words: Lyrics.hasSyncedLine ? Lyrics.lineWords : []
            lineStartMs: Lyrics.lineStartMs
            lineEndMs: Lyrics.lineEndMs
            playing: Lyrics.playing
            anchorPos: Lyrics.anchorPos
            anchorAt: Lyrics.anchorAt
            positionMs: Lyrics.positionMs
            isInterlude: root.isInterlude
            // A lyric source may enter/leave a short gap while the bar is
            // showing an MPRIS title. Do not let that unrelated state reset
            // the title marquee back to its start on every poll.
            holdLine: Lyrics.hasSyncedLine && Lyrics.holdLine
        }

    }

}
