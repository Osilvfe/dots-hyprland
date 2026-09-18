pragma ComponentBehavior: Bound

import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Item { // Wrapper
    id: root

    readonly property string xdgConfigHome: Directories.config
    readonly property int typingDebounceInterval: 200
    readonly property int typingResultLimit: 15 // Should be enough to cover the whole view
    readonly property bool clearBtnHasFocus: clearClipboardBtn.activeFocus || clearResultsBtn.activeFocus
    readonly property bool clipboardSearching: searchingText.startsWith(Config.options.search.prefix.clipboard) && searchingText.length > Config.options.search.prefix.clipboard.length

    property string searchingText: LauncherSearch.query
    property bool showResults: searchingText != ""
    property bool emojiMode: searchingText.startsWith(Config.options.search.prefix.emojis)
    implicitWidth: searchWidgetContent.implicitWidth + (root.isFluid ? 0 : Appearance.sizes.elevationMargin * 2)
    implicitHeight: searchWidgetContent.implicitHeight + (root.isFluid ? 0 : (searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2))
    width: implicitWidth
    height: searchWidgetContent.height + (root.isFluid ? 0 : (searchBar.verticalPadding * 2 + Appearance.sizes.elevationMargin * 2))

    function focusFirstItem() {
        if (appResults.count > 0) {
            appResults.currentIndex = 0;
            appResults.forceActiveFocus();
        }
    }

    function focusSearchInput() {
        searchBar.forceFocus();
    }

    function disableExpandAnimation() {
        searchBar.animateWidth = false;
    }

    function cancelSearch() {
        searchBar.searchInput.selectAll();
        LauncherSearch.query = "";
        searchBar.animateWidth = true;
    }

    function setSearchingText(text) {
        searchBar.searchInput.text = text;
        LauncherSearch.query = text;
    }

    Keys.onPressed: event => {
        // Prevent Esc and Backspace from registering
        if (event.key === Qt.Key_Escape)
            return;

        const clipNavKey = root.isFluid ? Qt.Key_Up : Qt.Key_Down;
        if (event.key === clipNavKey && searchingText.startsWith(Config.options.search.prefix.clipboard)) {
            if (clipboardSearching && !clearResultsBtn.activeFocus) {
                clearResultsBtn.forceActiveFocus();
                event.accepted = true;
                return;
            }
            if (!clearClipboardBtn.activeFocus) {
                clearClipboardBtn.forceActiveFocus();
                event.accepted = true;
                return;
            }
        }

        // Handle Backspace: focus and delete character if not focused
        if (event.key === Qt.Key_Backspace) {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                if (event.modifiers & Qt.ControlModifier) {
                    // Delete word before cursor
                    let text = searchBar.searchInput.text;
                    let pos = searchBar.searchInput.cursorPosition;
                    if (pos > 0) {
                        // Find the start of the previous word
                        let left = text.slice(0, pos);
                        let match = left.match(/(\s*\S+)\s*$/);
                        let deleteLen = match ? match[0].length : 1;
                        searchBar.searchInput.text = text.slice(0, pos - deleteLen) + text.slice(pos);
                        searchBar.searchInput.cursorPosition = pos - deleteLen;
                    }
                } else {
                    // Delete character before cursor if any
                    if (searchBar.searchInput.cursorPosition > 0) {
                        searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition - 1) + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                        searchBar.searchInput.cursorPosition -= 1;
                    }
                }
                // Always move cursor to end after programmatic edit
                searchBar.searchInput.cursorPosition = searchBar.searchInput.text.length;
                event.accepted = true;
            }
            // If already focused, let TextField handle it
            return;
        }

        // Only handle visible printable characters (ignore control chars, arrows, etc.)
        if (event.text && event.text.length === 1 && event.key !== Qt.Key_Enter && event.key !== Qt.Key_Return && event.key !== Qt.Key_Delete && event.text.charCodeAt(0) >= 0x20) // ignore control chars like Backspace, Tab, etc.
        {
            if (!searchBar.searchInput.activeFocus) {
                root.focusSearchInput();
                // Insert the character at the cursor position
                searchBar.searchInput.text = searchBar.searchInput.text.slice(0, searchBar.searchInput.cursorPosition) + event.text + searchBar.searchInput.text.slice(searchBar.searchInput.cursorPosition);
                searchBar.searchInput.cursorPosition += 1;
                event.accepted = true;
                root.focusFirstItem();
            }
        }
    }

    readonly property bool isFluid: Config.options.appearance.fluidMorphing.enable ?? false

    StyledRectangularShadow {
        target: searchWidgetContent
        visible: !root.isFluid
    }
    Rectangle { // Background
        id: searchWidgetContent
        anchors {
            top: root.isFluid ? undefined : parent.top
            bottom: root.isFluid ? parent.bottom : undefined
            horizontalCenter: parent.horizontalCenter
            topMargin: root.isFluid ? 0 : Appearance.sizes.elevationMargin
        }
        clip: true
        implicitWidth: Math.max(searchBarWrapper.implicitWidth, resultsWrapper.implicitWidth)
        implicitHeight: searchBarWrapper.implicitHeight + (root.showResults ? (separator.height + resultsWrapper.implicitHeight) : 0)
        width: implicitWidth
        height: implicitHeight
        radius: 28
        color: root.isFluid ? "transparent" : Appearance.colors.colBackgroundSurfaceContainer

        Behavior on height {
            id: searchHeightBehavior
            enabled: GlobalStates.overviewOpen
            NumberAnimation {
                duration: root.isFluid ? 80 : 160
                easing.type: Easing.OutCubic
            }
        }

        Item {
            id: searchBarWrapper
            anchors {
                left: parent.left
                right: parent.right
                top: root.isFluid ? undefined : parent.top
                bottom: root.isFluid ? parent.bottom : undefined
            }
            implicitHeight: searchBar.implicitHeight + searchBar.verticalPadding * 2
            implicitWidth: searchBar.implicitWidth + 20

            SearchBar {
                id: searchBar
                property real verticalPadding: 4
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 10
                    rightMargin: 4
                }
                Synchronizer on searchingText {
                    property alias source: root.searchingText
                }
                onNavigateResults: {
                    root.focusFirstItem();
                }
            }
        }

        Rectangle {
            id: separator
            visible: root.showResults
            height: 1
            color: Appearance.colors.colOutlineVariant
            anchors {
                left: parent.left
                right: parent.right
                top: root.isFluid ? undefined : searchBarWrapper.bottom
                bottom: root.isFluid ? searchBarWrapper.top : undefined
            }
        }

        Item {
            id: resultsWrapper
            visible: root.showResults
            clip: true
            anchors {
                left: parent.left
                right: parent.right
                top: root.isFluid ? parent.top : separator.bottom
                bottom: root.isFluid ? separator.top : parent.bottom
            }
            implicitHeight: resultsColumn.implicitHeight
            implicitWidth: resultsColumn.implicitWidth

            ColumnLayout {
                id: resultsColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: root.isFluid ? undefined : parent.top
                anchors.bottom: root.isFluid ? parent.bottom : undefined
                spacing: 0

                layer.enabled: !root.isFluid
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: searchWidgetContent.width
                        height: searchWidgetContent.height
                        radius: searchWidgetContent.radius
                    }
                }

                RowLayout {
                    id: clipboardHeader
                    visible: root.showResults && root.searchingText.startsWith(Config.options.search.prefix.clipboard)
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    Layout.rightMargin: 10
                    Layout.topMargin: 6
                    Layout.bottomMargin: 2

                    StyledText {
                        text: Translation.tr("Clipboard")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    Item { Layout.fillWidth: true }

                    Button {
                        id: clearResultsBtn
                        visible: root.clipboardSearching
                        implicitHeight: 28
                        hoverEnabled: true
                        contentItem: StyledText {
                            text: Translation.tr("Clear results")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: clearResultsBtn.focus ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: clearResultsBtn.down ? Appearance.colors.colPrimaryContainerActive : (clearResultsBtn.hovered ? Appearance.colors.colPrimaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1))
                            border.width: clearResultsBtn.focus ? 2 : 0
                            border.color: Appearance.colors.colSecondary
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }
                        onClicked: {
                            const query = StringUtils.cleanPrefix(root.searchingText, Config.options.search.prefix.clipboard);
                            Cliphist.deleteEntries(Cliphist.fuzzyQuery(query));
                            root.focusSearchInput();
                        }
                        KeyNavigation.right: clearClipboardBtn
                        KeyNavigation.down: appResults
                    }

                    Button {
                        id: clearClipboardBtn
                        implicitHeight: 28
                        hoverEnabled: true
                        contentItem: StyledText {
                            text: Translation.tr("Clear all")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: clearClipboardBtn.focus ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colPrimary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            radius: Appearance.rounding.small
                            color: clearClipboardBtn.down ? Appearance.colors.colPrimaryContainerActive : (clearClipboardBtn.hovered ? Appearance.colors.colPrimaryContainer : ColorUtils.transparentize(Appearance.colors.colPrimaryContainer, 1))
                            border.width: clearClipboardBtn.focus ? 2 : 0
                            border.color: Appearance.colors.colSecondary
                            Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                        }
                        onClicked: {
                            Cliphist.wipe();
                            root.focusSearchInput();
                        }
                        KeyNavigation.left: root.clipboardSearching ? clearResultsBtn : searchBar
                        KeyNavigation.down: appResults
                    }
                }

                Item {
                    id: clipboardEmpty
                    visible: root.showResults && root.searchingText.startsWith(Config.options.search.prefix.clipboard) && appResults.count === 0
                    Layout.fillWidth: true
                    implicitHeight: 120
                    readonly property bool hasEntries: Cliphist.entries.length > 0
                    readonly property bool isSearching: hasEntries && root.clipboardSearching

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 48
                            color: Appearance.m3colors.m3outline
                            text: parent.parent.isSearching ? "search_off" : "content_paste"
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.m3colors.m3outline
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.parent.isSearching ? Translation.tr("No results found") : Translation.tr("Clipboard is empty")
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.m3colors.m3outline
                            horizontalAlignment: Text.AlignHCenter
                            text: parent.parent.isSearching ? Translation.tr("Try a different search") : Translation.tr("Copy something to see it here")
                        }
                    }
                }

                ListView { // App results
                    id: appResults
                    visible: root.showResults && !root.emojiMode && !clipboardEmpty.visible
                    Layout.fillWidth: true
                    readonly property real estimatedHeight: {
                        if (!visible || count === 0) return 0;
                        const naturalH = contentHeight > 0 ? (contentHeight + topMargin + bottomMargin)
                                                           : (Math.min(root.typingResultLimit, count) * 48 + topMargin + bottomMargin);
                        return Math.min(500, naturalH);
                    }
                    implicitHeight: estimatedHeight
                    Layout.preferredHeight: estimatedHeight
                    clip: true
                    topMargin: 8
                    bottomMargin: 8
                    spacing: 2
                    KeyNavigation.up: root.isFluid ? null : searchBar
                    KeyNavigation.down: root.isFluid ? searchBar : null
                    highlightMoveDuration: 100

                    Connections {
                        target: root
                        function onSearchingTextChanged() {
                            if (appResults.count > 0)
                                appResults.currentIndex = 0;
                        }
                    }

                    Connections {
                        target: LauncherSearch
                        function onResultsChanged() {
                            resultModel.values = LauncherSearch.results ? LauncherSearch.results.slice(0, root.typingResultLimit) : [];
                            root.focusFirstItem();
                        }
                    }

                    model: ScriptModel {
                        id: resultModel
                        objectProp: "key"
                    }

                    delegate: SearchItem {
                        id: searchItem
                        // The selectable item for each search result
                        required property var modelData
                        required property int index
                        anchors.left: parent?.left
                        anchors.right: parent?.right
                        entry: modelData
                        clearBtnHasFocus: root.clearBtnHasFocus
                        query: StringUtils.cleanOnePrefix(root.searchingText, [Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch])

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab) {
                                if (LauncherSearch.results.length === 0)
                                    return;
                                const tabbedText = searchItem.modelData.name;
                                LauncherSearch.query = tabbedText;
                                searchBar.searchInput.text = tabbedText;
                                event.accepted = true;
                                root.focusSearchInput();
                            } else if (event.key === Qt.Key_Up && searchItem.index === 0 && root.searchingText.startsWith(Config.options.search.prefix.clipboard)) {
                                (root.clipboardSearching ? clearResultsBtn : clearClipboardBtn).forceActiveFocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && searchItem.index === searchItem.ListView.view.count - 1) {
                                if (root.isFluid) {
                                    root.focusSearchInput();
                                }
                                event.accepted = true;
                            }
                        }
                    }
                }

                GridView { // Emoji results (grid picker)
                    id: emojiGrid
                    visible: root.showResults && root.emojiMode
                    Layout.fillWidth: true
                    Layout.preferredHeight: 360
                    clip: true
                    topMargin: 10
                    bottomMargin: 10
                    cellWidth: 56
                    cellHeight: 56
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    KeyNavigation.up: root.isFluid ? null : searchBar
                    KeyNavigation.down: root.isFluid ? searchBar : null
                    highlightMoveDuration: 100

                    Connections {
                        target: root
                        function onSearchingTextChanged() {
                            if (emojiGrid.count > 0)
                                emojiGrid.currentIndex = 0;
                            emojiDebounce.restart();
                        }
                    }

                    Timer {
                        id: emojiDebounce
                        interval: root.typingDebounceInterval
                        onTriggered: {
                            emojiResultModel.values = LauncherSearch.results.slice(0, 300);
                        }
                    }

                    Connections {
                        target: LauncherSearch
                        function onResultsChanged() {
                            emojiDebounce.restart();
                        }
                    }

                    model: ScriptModel {
                        id: emojiResultModel
                        objectProp: "key"
                    }

                    delegate: RippleButton {
                        id: emojiCell
                        required property var modelData
                        implicitWidth: emojiGrid.cellWidth - 4
                        implicitHeight: emojiGrid.cellHeight - 4
                        buttonRadius: Appearance.rounding.normal
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        colRipple: Appearance.colors.colLayer2Active

                        contentItem: StyledText {
                            anchors.centerIn: parent
                            text: modelData.iconName ?? ""
                            font.pixelSize: Appearance.font.pixelSize.huge + 6
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            GlobalStates.overviewOpen = false
                            modelData.execute()
                        }

                        StyledToolTip {
                            text: modelData.name ?? ""
                        }
                    }
                }
            }
        }
    }
}
