pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
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

    readonly property string cacheDir: FileUtils.trimFileProtocol(`${Directories.state}/holidays`)
    readonly property int cacheMaxAgeMs: 7 * 24 * 3600 * 1000
    // map "YYYY-MM-DD" -> { name: festival day name or "", isOffDay: bool or null }
    property var data: ({})
    property bool loading: false
    property int currentYear: new Date().getFullYear()
    property int pendingYear: 0
    property var fetchQueue: []
    property var yearsLoaded: ({})
    property bool offDone: false
    property bool festivalDone: false
    property var offData: ({})
    property var festivalData: ({})

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
        year = Number(year);
        if (!year)
            return;
        if (root.pendingYear === year)
            return;
        if (root.fetchQueue.indexOf(year) !== -1)
            return;
        if (root.yearsLoaded[year])
            return;
        if (root.loading) {
            root.fetchQueue = [...root.fetchQueue, year];
            return;
        }
        root.startFetch(year);
    }

    function startFetch(year) {
        root.loading = true;
        root.pendingYear = year;
        root.offDone = false;
        root.festivalDone = false;
        root.offData = {};
        root.festivalData = {};
        cacheFileView.path = Qt.resolvedUrl(root.cachePath(String(year)));
        cacheFileView.reload();
    }

    function dequeue() {
        root.loading = false;
        root.pendingYear = 0;
        if (root.fetchQueue.length > 0) {
            const next = root.fetchQueue[0];
            root.fetchQueue = root.fetchQueue.slice(1);
            root.startFetch(next);
        }
    }

    function stripMeta(obj) {
        const out = {};
        for (const key in obj) {
            if (key !== "_meta")
                out[key] = obj[key];
        }
        return out;
    }

    function isCacheStale(obj) {
        const ts = obj?._meta?.fetchedAt;
        if (!ts)
            return true;
        return (Date.now() - ts) > root.cacheMaxAgeMs;
    }

    function mergeIntoData(dayMap) {
        const merged = Object.assign({}, root.data);
        for (const key in dayMap) {
            merged[key] = dayMap[key];
        }
        root.data = merged;
    }

    function markYearLoaded(year) {
        const loaded = Object.assign({}, root.yearsLoaded);
        loaded[year] = true;
        root.yearsLoaded = loaded;
    }

    function writeYearCache(year, dayMap) {
        const payload = JSON.stringify(Object.assign({
            _meta: {
                fetchedAt: Date.now(),
                year: year
            }
        }, dayMap));
        const path = root.cachePath(year);
        Quickshell.execDetached(["bash", "-c", "printf '%s' \"$1\" > \"$2\"", "_", payload, path]);
    }

    // Fetch both sources; merge into root.data
    function loadRemote(year) {
        root.offDone = false;
        root.festivalDone = false;
        offFetcher.command = ["bash", "-c",
            `curl -sS --fail --max-time 15 "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/${year}.json"`];
        festivalFetcher.command = ["bash", "-c",
            `curl -sS --fail --max-time 15 "https://date.nager.at/api/v3/PublicHolidays/${year}/CN"`];
        offFetcher.running = true;
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

    function applyCache(text) {
        if (!text)
            return {};
        const parsed = root.parseMergedCache(text);
        const days = root.stripMeta(parsed);
        if (Object.keys(days).length > 0)
            root.mergeIntoData(days);
        return parsed;
    }

    // Read cached file; if missing or stale, fetch remote
    FileView {
        id: cacheFileView
        path: Qt.resolvedUrl(root.cachePath(String(root.currentYear)))
        onLoadFailed: (error) => {
            if (!root.pendingYear) {
                root.loading = false;
                return;
            }
            if (error == FileViewError.FileNotFound) {
                root.loadRemote(root.pendingYear);
            } else {
                root.dequeue();
            }
        }
        onFileChanged: {
            // Writes go through execDetached, not this FileView
        }
        onLoaded: {
            if (!root.pendingYear)
                return;
            const content = cacheFileView.text();
            const parsed = root.applyCache(content);
            if (content && Object.keys(root.stripMeta(parsed)).length > 0 && !root.isCacheStale(parsed)) {
                root.markYearLoaded(root.pendingYear);
                root.dequeue();
                return;
            }
            root.loadRemote(root.pendingYear);
        }
    }

    // Cache stores a merged JSON: { "_meta": { fetchedAt, year }, "date": { name, isOffDay }, ... }
    function parseMergedCache(text) {
        try {
            return JSON.parse(text) ?? {};
        } catch (e) {
            console.error(`[Holidays] cache parse error: ${e.message}`);
            return {};
        }
    }

    Process {
        id: offFetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            id: offOut
        }
        onExited: (exitCode, exitStatus) => {
            if (offOut.text.length > 0)
                root.offData = root.parseOffData(offOut.text);
            root.offDone = true;
            root.maybeFinishLoad();
        }
    }

    Process {
        id: festivalFetcher
        command: ["bash", "-c", ""]
        stdout: StdioCollector {
            id: festivalOut
        }
        onExited: (exitCode, exitStatus) => {
            if (festivalOut.text.length > 0)
                root.festivalData = root.parseFestivalData(festivalOut.text);
            root.festivalDone = true;
            root.maybeFinishLoad();
        }
    }

    function maybeFinishLoad() {
        if (!root.offDone || !root.festivalDone)
            return;
        const merged = root.mergeData(root.offData, root.festivalData);
        if (Object.keys(merged).length > 0) {
            root.mergeIntoData(merged);
            root.writeYearCache(root.pendingYear, merged);
        }
        root.markYearLoaded(root.pendingYear);
        root.dequeue();
    }

    Component.onCompleted: {
        root.ensureCacheDir();
        const year = new Date().getFullYear();
        root.currentYear = year;
        root.fetchYear(year);
        root.fetchYear(year - 1);
        root.fetchYear(year + 1);
    }
}
