pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

// Chinese holidays from two sources:
//  - Nager.Date  -> the actual festival day names (春节/端午/中秋/… exact dates)
//  - holiday-cn  -> which days are off (isOffDay) / make-up workdays within the
//                   government-arranged holiday period
// Cached per-year in Directories.state so the calendar works offline.
Singleton {
    id: root

    readonly property string cacheDir: `${Directories.state}/holidays`
    // map "YYYY-MM-DD" -> { name: festival day name or "", isOffDay: bool or null }
    property var data: ({})
    property bool loading: false
    property int currentYear: new Date().getFullYear()

    function cachePath(year) {
        return `${root.cacheDir}/${year}.json`;
    }

    // Returns holiday info for a date or null
    function holidayFor(year, month, day) {
        const key = `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
        return root.data[key] ?? null;
    }

    function ensureCacheDir() {
        Quickshell.execDetached(["mkdir", "-p", root.cacheDir]);
    }

    function fetchYear(year) {
        if (root.loading)
            return;
        root.loading = true;
        cacheFileView.path = Qt.resolvedUrl(root.cachePath(String(year)));
        cacheFileView.reload();
    }

    // Fetch both sources; merge into root.data
    function loadRemote(year) {
        offFetcher.command = ["bash", "-c",
            `curl -s --max-time 15 "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/${year}.json"`];
        offFetcher.running = true;
        festivalFetcher.command = ["bash", "-c",
            `curl -s --max-time 15 "https://date.nager.at/api/v3/PublicHolidays/${year}/CN"`];
        festivalFetcher.running = true;
    }

    function parseOffData(text) {
        const out = {};
        try {
            const parsed = JSON.parse(text);
            if (!parsed?.days)
                return out;
            for (const day of parsed.days) {
                if (day?.date) {
                    out[day.date] = { name: "", isOffDay: !!day.isOffDay };
                }
            }
        } catch (e) {
            console.error(`[Holidays] off parse error: ${e.message}`);
        }
        return out;
    }

    function parseFestivalData(text) {
        const out = {};
        try {
            const parsed = JSON.parse(text);
            for (const day of parsed) {
                if (day?.date && day?.localName) {
                    out[day.date] = { name: day.localName, isOffDay: null };
                }
            }
        } catch (e) {
            console.error(`[Holidays] festival parse error: ${e.message}`);
        }
        return out;
    }

    function mergeData(offMap, festivalMap) {
        const merged = {};
        for (const key in offMap) {
            merged[key] = { name: festivalMap[key]?.name ?? "", isOffDay: offMap[key].isOffDay };
        }
        for (const key in festivalMap) {
            if (!(key in merged)) {
                merged[key] = { name: festivalMap[key].name, isOffDay: null };
            }
        }
        return merged;
    }

    // Read cached file; if missing, fetch remote
    FileView {
        id: cacheFileView
        path: Qt.resolvedUrl(root.cachePath(String(root.currentYear)))
        onLoadFailed: (error) => {
            if (error == FileViewError.FileNotFound) {
                root.loadRemote(root.currentYear);
            } else {
                root.loading = false;
            }
        }
        onFileChanged: {
            const content = cacheFileView.text();
            if (content) {
                root.data = root.parseMergedCache(content);
            }
            root.loading = false;
        }
        onLoaded: {
            const content = cacheFileView.text();
            if (content) {
                root.data = root.parseMergedCache(content);
            }
            root.loading = false;
        }
    }

    // Cache stores a merged JSON: { "date": { name, isOffDay }, ... }
    function parseMergedCache(text) {
        try {
            return JSON.parse(text) ?? {};
        } catch (e) {
            console.error(`[Holidays] cache parse error: ${e.message}`);
            return {};
        }
    }

    property var offData: ({})
    property var festivalData: ({})

    Process {
        id: offFetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    root.offData = root.parseOffData(text);
                root.maybeFinishLoad();
            }
        }
    }

    Process {
        id: festivalFetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length > 0)
                    root.festivalData = root.parseFestivalData(text);
                root.maybeFinishLoad();
            }
        }
    }

    function maybeFinishLoad() {
        if (offFetcher.running || festivalFetcher.running)
            return;
        root.data = root.mergeData(root.offData, root.festivalData);
        cacheFileView.setText(JSON.stringify(root.data));
        root.loading = false;
    }

    onLoadingChanged: {
        if (root.loading) {
            root.offData = {};
            root.festivalData = {};
        }
    }

    Component.onCompleted: {
        root.ensureCacheDir();
        root.fetchYear(root.currentYear);
    }
}
