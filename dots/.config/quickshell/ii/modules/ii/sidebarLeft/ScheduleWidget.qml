import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    // schedule.json (kept backward compatible):
    // { semesterStart: "2026-09-07", showWeekend: true, timeHeaders: ["第1节"],
    //   scheduleItems: [{ text, col, row, rowSpan, colorId,
    //     weeks: [1, 2], weekStart: 1, weekEnd: 16, weekType: "all|odd|even" }] }
    // `weeks` takes precedence when present. Old entries without week data are shown every week.
    property var scheduleItems: []
    property var timeHeaders: []
    property string semesterStart: ""
    property bool showWeekend: true
    property var headers: ["一", "二", "三", "四", "五", "六", "日"]
    property bool settingsOpen: false
    property var editTimeHeaders: []
    property bool editShowWeekend: true
    property int timeW: 40
    property int cellW: 52
    property int cellH: 52
    property int headerH: 24
    property int gap: 4
    readonly property int periodCount: Math.max(timeHeaders.length, 4)
    property var currentDate: new Date()
    readonly property int currentWeek: weekForDate(currentDate)
    property int selectedWeek: 1
    readonly property int maxWeek: scheduleMaxWeek()
    readonly property string termState: termStatus()
    readonly property int visibleDayCount: showWeekend ? 7 : 5
    property string filePath: Directories.scheduleCache

    function dateFromIso(value) {
        var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || "");
        if (!match)
            return null;

        var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
        return isNaN(date.getTime()) ? null : date;
    }

    function weekForDate(date) {
        var start = dateFromIso(semesterStart);
        if (!start)
            return 0;

        var today = new Date(date.getFullYear(), date.getMonth(), date.getDate());
        var days = Math.floor((today.getTime() - start.getTime()) / 8.64e+07);
        return days < 0 ? 0 : Math.floor(days / 7) + 1;
    }

    function courseIsInWeek(course, week) {
        if (!week || course.isEmpty)
            return true;

        if (Array.isArray(course.weeks) && course.weeks.length > 0)
            return course.weeks.indexOf(week) !== -1;

        var first = Number(course.weekStart || 0);
        var last = Number(course.weekEnd || 0);
        if (first && week < first || last && week > last)
            return false;

        if (course.weekType === "odd")
            return week % 2 === 1;

        if (course.weekType === "even")
            return week % 2 === 0;

        return true;
    }

    function scheduleMaxWeek() {
        var maximum = 18;
        for (var index = 0; index < scheduleItems.length; index++) {
            var course = scheduleItems[index];
            if (Array.isArray(course.weeks) && course.weeks.length)
                maximum = Math.max(maximum, Math.max.apply(null, course.weeks));

            maximum = Math.max(maximum, Number(course.weekEnd || 0), Number(course.weekStart || 0));
        }
        return maximum;
    }

    function termStatus() {
        if (!semesterStart)
            return "unset";

        if (currentWeek < 1)
            return "before";

        if (currentWeek > maxWeek)
            return "after";

        return "active";
    }

    function courseLayoutKey(course) {
        return JSON.stringify({
            "text": course.text || "",
            "teacher": course.teacher || "",
            "location": course.location || "",
            "colorId": course.colorId || 0,
            "weeks": course.weeks || [],
            "weekStart": course.weekStart || 0,
            "weekEnd": course.weekEnd || 0,
            "weekType": course.weekType || "all"
        });
    }

    // Rendering can merge a course spanning adjacent sections without changing
    // the imported source records. It keeps courses with differing weeks apart.
    function mergedScheduleItems() {
        var sorted = scheduleItems.slice().sort((left, right) => {
            return left.col - right.col || left.row - right.row;
        });
        var merged = [];
        for (var index = 0; index < sorted.length; index++) {
            var course = sorted[index];
            var previous = merged.length ? merged[merged.length - 1] : null;
            if (previous && previous.col === course.col && previous.row + previous.rowSpan === course.row && courseLayoutKey(previous) === courseLayoutKey(course))
                previous.rowSpan += course.rowSpan;
            else
                merged.push(Object.assign({
                }, course));
        }
        return merged;
    }

    function getColor(id) {
        var colors = [Appearance.colors.colPrimaryContainer, Appearance.colors.colSecondaryContainer, Appearance.colors.colTertiaryContainer, ColorUtils.transparentize(Appearance.colors.colErrorContainer, 0.6), Appearance.colors.colLayer2Hover];
        return colors[id % colors.length];
    }

    function getTextColor(id) {
        var colors = [Appearance.colors.colOnPrimaryContainer, Appearance.colors.colOnSecondaryContainer, Appearance.colors.colOnTertiaryContainer, Appearance.colors.colOnErrorContainer, Appearance.colors.colOnSurfaceVariant];
        return colors[id % colors.length];
    }

    function openSettings() {
        editTimeHeaders = timeHeaders.length ? timeHeaders.slice() : ["第1节", "第2节", "第3节", "第4节", "第5节", "第6节", "第7节", "第8节", "第9节", "第10节"];
        editShowWeekend = showWeekend;
        settingsOpen = true;
    }

    function saveSettings() {
        var start = startDateField.text.trim();
        if (start && !dateFromIso(start)) {
            settingsError.text = "日期格式应为 YYYY-MM-DD";
            return ;
        }
        var periods = editTimeHeaders.map((value) => {
            return value.trim();
        }).filter((value) => {
            return value.length > 0;
        });
        semesterStart = start;
        timeHeaders = periods;
        showWeekend = editShowWeekend;
        scheduleFile.setText(JSON.stringify({
            "semesterStart": semesterStart,
            "showWeekend": showWeekend,
            "timeHeaders": timeHeaders,
            "scheduleItems": scheduleItems
        }, null, 2));
        settingsOpen = false;
    }

    implicitWidth: timeW + visibleDayCount * (cellW + gap) + gap + 16
    implicitHeight: 310
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", FileUtils.parentDirectory(filePath)])
    onCurrentWeekChanged: {
        if (currentWeek > 0 && currentWeek <= maxWeek)
            selectedWeek = currentWeek;

    }

    // Keep the displayed week correct if the shell stays up across midnight.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.currentDate = new Date()
    }

    FileView {
        id: scheduleFile

        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onLoaded: {
            try {
                var text = scheduleFile.text();
                if (!text.trim())
                    return ;

                var parsed = JSON.parse(text);
                root.semesterStart = parsed.semesterStart || parsed.firstWeekDate || "";
                root.showWeekend = parsed.showWeekend !== false;
                root.timeHeaders = parsed.timeHeaders || [];
                root.scheduleItems = parsed.scheduleItems || [];
                if (root.currentWeek > 0 && root.currentWeek <= root.maxWeek)
                    root.selectedWeek = root.currentWeek;

            } catch (error) {
                console.log("schedule:", error);
            }
        }
        onLoadFailed: function(error) {
            if (error !== FileViewError.FileNotFound)
                console.log("schedule load fail:", error, "path:", path);

        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8

            RippleButtonWithIcon {
                materialIcon: "chevron_left"
                mainText: ""
                implicitWidth: 34
                enabled: root.selectedWeek > 1
                onClicked: root.selectedWeek--
            }

            StyledText {
                Layout.fillWidth: true
                text: `${root.termState === "before" ? "未开学 · " : root.termState === "after" ? "学期结束 · " : root.termState === "unset" ? "未设置开学日期 · " : ""}第 ${root.selectedWeek} / ${root.maxWeek} 周`
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.smaller
                horizontalAlignment: Text.AlignHCenter
            }

            RippleButtonWithIcon {
                materialIcon: "chevron_right"
                mainText: ""
                implicitWidth: 34
                enabled: root.selectedWeek < root.maxWeek
                onClicked: root.selectedWeek++
            }

        }

        Flickable {
            id: flick

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 8
            clip: true
            contentWidth: root.timeW + root.visibleDayCount * (root.cellW + root.gap) + root.gap
            contentHeight: root.headerH + root.periodCount * (root.cellH + root.gap) + root.gap
            boundsBehavior: Flickable.StopAtBounds

            Item {
                width: flick.contentWidth
                height: flick.contentHeight

                StyledText {
                    width: root.timeW
                    height: root.headerH
                    text: "时间"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Row {
                    x: root.timeW + root.gap
                    spacing: root.gap

                    Repeater {
                        model: root.headers.slice(0, root.visibleDayCount)

                        Rectangle {
                            width: root.cellW
                            height: root.headerH
                            color: "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnSurfaceVariant
                            }

                        }

                    }

                }

                Column {
                    y: root.headerH + root.gap
                    spacing: root.gap

                    Repeater {
                        model: root.periodCount

                        Rectangle {
                            width: root.timeW
                            height: root.cellH
                            color: "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: root.timeHeaders[index] ? root.timeHeaders[index].replace(" - ", "\n") : (index + 1).toString()
                                font.pixelSize: 9
                                color: Appearance.colors.colOutline
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                        }

                    }

                }

                Repeater {
                    model: root.mergedScheduleItems()

                    Rectangle {
                        visible: modelData.col < root.visibleDayCount && root.courseIsInWeek(modelData, root.selectedWeek)
                        x: root.timeW + root.gap + modelData.col * (root.cellW + root.gap)
                        y: root.headerH + root.gap + modelData.row * (root.cellH + root.gap)
                        width: root.cellW
                        height: root.cellH * modelData.rowSpan + root.gap * (modelData.rowSpan - 1)
                        radius: 6
                        color: modelData.isEmpty ? "transparent" : root.getColor(modelData.colorId)

                        StyledText {
                            anchors.fill: parent
                            anchors.margins: 3
                            text: modelData.isEmpty ? "" : `${modelData.text}${modelData.location ? "\n" + modelData.location : ""}`
                            color: root.getTextColor(modelData.colorId)
                            font.pixelSize: 8
                            font.weight: Font.Bold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                        }

                    }

                }

            }

        }

        RippleButtonWithIcon {
            Layout.alignment: Qt.AlignHCenter
            materialIcon: "settings"
            mainText: "课表设置"
            onClicked: root.openSettings()
        }

    }

    Rectangle {
        visible: root.settingsOpen
        anchors.fill: parent
        z: 10
        radius: Appearance.rounding.small
        // Settings must stay readable even when the sidebar transparency option is enabled.
        color: Appearance.m3colors.m3surfaceContainerHigh

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    text: "课表设置"
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                }

                Item {
                    Layout.fillWidth: true
                }

                RippleButtonWithIcon {
                    materialIcon: "close"
                    mainText: ""
                    implicitWidth: 34
                    onClicked: root.settingsOpen = false
                }

            }

            StyledText {
                text: "第一周开始日期"
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            MaterialTextField {
                id: startDateField

                Layout.fillWidth: true
                placeholderText: "例如 2026-09-07"
                text: root.semesterStart
            }

            RowLayout {
                Layout.fillWidth: true

                StyledText {
                    Layout.fillWidth: true
                    text: "显示周六、周日"
                    color: Appearance.colors.colOnSurfaceVariant
                    font.pixelSize: Appearance.font.pixelSize.small
                }

                StyledSwitch {
                    checked: root.editShowWeekend
                    onToggled: root.editShowWeekend = checked
                }

            }

            StyledText {
                text: "时间段"
                color: Appearance.colors.colOnSurfaceVariant
                font.pixelSize: Appearance.font.pixelSize.small
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: periodEditor.implicitHeight

                ColumnLayout {
                    id: periodEditor

                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.editTimeHeaders.length

                        RowLayout {
                            required property int index

                            Layout.fillWidth: true

                            StyledText {
                                text: `${index + 1}`
                                Layout.preferredWidth: 18
                                horizontalAlignment: Text.AlignHCenter
                            }

                            MaterialTextField {
                                Layout.fillWidth: true
                                placeholderText: "例如 08:00 - 08:45"
                                text: root.editTimeHeaders[index]
                                onTextEdited: {
                                    root.editTimeHeaders[index] = text;
                                    root.editTimeHeaders = root.editTimeHeaders.slice();
                                }
                            }

                            RippleButtonWithIcon {
                                materialIcon: "remove"
                                mainText: ""
                                implicitWidth: 34
                                onClicked: {
                                    root.editTimeHeaders.splice(index, 1);
                                    root.editTimeHeaders = root.editTimeHeaders.slice();
                                }
                            }

                        }

                    }

                    RippleButtonWithIcon {
                        Layout.fillWidth: true
                        materialIcon: "add"
                        mainText: "添加时间段"
                        onClicked: root.editTimeHeaders = root.editTimeHeaders.concat([""])
                    }

                }

            }

            StyledText {
                id: settingsError

                Layout.fillWidth: true
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight

                RippleButtonWithIcon {
                    materialIcon: "close"
                    mainText: "取消"
                    onClicked: root.settingsOpen = false
                }

                RippleButtonWithIcon {
                    materialIcon: "save"
                    mainText: "保存"
                    onClicked: root.saveSettings()
                }

            }

        }

    }

}
