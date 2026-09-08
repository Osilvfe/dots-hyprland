import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.models
import qs.services
pragma Singleton

Singleton {
    id: root

    function inspect(str) {
        if (!str || typeof str !== "string")
            return null;

        const trimmed = str.trim();
        if (trimmed.length === 0)
            return null;

        // Try detectors in order of specificity
        const color = inspectColor(trimmed);
        if (color)
            return color;

        const math = inspectMath(trimmed);
        if (math)
            return math;

        const timestamp = inspectTimestamp(trimmed);
        if (timestamp)
            return timestamp;

        const url = inspectUrl(trimmed);
        if (url)
            return url;

        const path = inspectPath(trimmed);
        if (path)
            return path;

        const json = inspectJson(trimmed);
        if (json)
            return json;

        const base64 = inspectBase64(trimmed);
        if (base64)
            return base64;

        return null;
    }

    function inspectColor(str) {
        if (!str || str.length < 3 || str.length > 40)
            return null;

        const trimmed = str.trim();
        // 1. Hex: #rgb, #rgba, #rrggbb, #rrggbbaa
        const hexMatch = trimmed.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/);
        if (hexMatch) {
            const hex = hexMatch[1];
            let r = 0, g = 0, b = 0, a = 1;
            if (hex.length === 3) {
                r = parseInt(hex[0] + hex[0], 16);
                g = parseInt(hex[1] + hex[1], 16);
                b = parseInt(hex[2] + hex[2], 16);
            } else if (hex.length === 4) {
                r = parseInt(hex[0] + hex[0], 16);
                g = parseInt(hex[1] + hex[1], 16);
                b = parseInt(hex[2] + hex[2], 16);
                a = parseInt(hex[3] + hex[3], 16) / 255;
            } else if (hex.length === 6) {
                r = parseInt(hex.slice(0, 2), 16);
                g = parseInt(hex.slice(2, 4), 16);
                b = parseInt(hex.slice(4, 6), 16);
            } else if (hex.length === 8) {
                r = parseInt(hex.slice(0, 2), 16);
                g = parseInt(hex.slice(2, 4), 16);
                b = parseInt(hex.slice(4, 6), 16);
                a = parseInt(hex.slice(6, 8), 16) / 255;
            }
            return buildColorResult(r, g, b, a, "hex");
        }
        // 2. RGB / RGBA
        const rgbMatch = trimmed.match(/^rgba?\(\s*(\d{1,3}%?)\s*[, ]\s*(\d{1,3}%?)\s*[, ]\s*(\d{1,3}%?)(?:\s*[,/]\s*([\d.]+%?))?\s*\)$/i);
        if (rgbMatch) {
            const parseComp = (c) => {
                return c.endsWith("%") ? Math.round(parseFloat(c) * 2.55) : parseInt(c, 10);
            };
            const parseAlpha = (a) => {
                if (!a)
                    return 1;

                return a.endsWith("%") ? parseFloat(a) / 100 : parseFloat(a);
            };
            const r = Math.min(255, Math.max(0, parseComp(rgbMatch[1])));
            const g = Math.min(255, Math.max(0, parseComp(rgbMatch[2])));
            const b = Math.min(255, Math.max(0, parseComp(rgbMatch[3])));
            const a = Math.min(1, Math.max(0, parseAlpha(rgbMatch[4])));
            return buildColorResult(r, g, b, a, "rgb");
        }
        // 3. HSL / HSLA
        const hslMatch = trimmed.match(/^hsla?\(\s*(\d{1,3}(?:deg)?)\s*[, ]\s*([\d.]+%)\s*[, ]\s*([\d.]+%)(?:\s*[,/]\s*([\d.]+%?))?\s*\)$/i);
        if (hslMatch) {
            const h = parseInt(hslMatch[1], 10) % 360;
            const s = parseFloat(hslMatch[2]) / 100;
            const l = parseFloat(hslMatch[3]) / 100;
            const a = hslMatch[4] ? (hslMatch[4].endsWith("%") ? parseFloat(hslMatch[4]) / 100 : parseFloat(hslMatch[4])) : 1;
            const k = (n) => {
                return (n + h / 30) % 12;
            };
            const f = (n) => {
                return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k(n) - 3, Math.min(9 - k(n), 1)));
            };
            const r = Math.round(255 * f(0));
            const g = Math.round(255 * f(8));
            const b = Math.round(255 * f(4));
            return buildColorResult(r, g, b, a, "hsl");
        }
        return null;
    }

    function buildColorResult(r, g, b, a, originalFormat) {
        const toHex2 = (n) => {
            const h = Math.round(n).toString(16).toUpperCase();
            return h.length < 2 ? "0" + h : h;
        };
        const hex = a < 1 ? `#${toHex2(r)}${toHex2(g)}${toHex2(b)}${toHex2(Math.round(a * 255))}` : `#${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
        const rgb = a < 1 ? `rgba(${r}, ${g}, ${b}, ${parseFloat(a.toFixed(2))})` : `rgb(${r}, ${g}, ${b})`;
        // RGB to HSL
        const rNorm = r / 255, gNorm = g / 255, bNorm = b / 255;
        const max = Math.max(rNorm, gNorm, bNorm), min = Math.min(rNorm, gNorm, bNorm);
        let h = 0, s = 0, l = (max + min) / 2;
        if (max !== min) {
            const d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            switch (max) {
            case rNorm:
                h = (gNorm - bNorm) / d + (gNorm < bNorm ? 6 : 0);
                break;
            case gNorm:
                h = (bNorm - rNorm) / d + 2;
                break;
            case bNorm:
                h = (rNorm - gNorm) / d + 4;
                break;
            }
            h = Math.round(h * 60);
        }
        const hsl = a < 1 ? `hsla(${h}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%, ${parseFloat(a.toFixed(2))})` : `hsl(${h}, ${Math.round(s * 100)}%, ${Math.round(l * 100)}%)`;
        return {
            "type": "color",
            "r": r,
            "g": g,
            "b": b,
            "a": a,
            "hex": hex,
            "rgb": rgb,
            "hsl": hsl,
            "originalFormat": originalFormat,
            "qmlColor": hex
        };
    }

    function inspectMath(expr) {
        if (!expr || expr.length < 3 || expr.length > 80)
            return null;

        const trimmed = expr.trim();
        // Skip pure numbers or paths or colors
        if (/^[0-9]+(\.[0-9]+)?$/.test(trimmed))
            return null;

        if (/^[\/.~#]/.test(trimmed))
            return null;

        if (/["'`\\]/.test(trimmed))
            return null;

        // Must contain arithmetic operators or functions
        if (!/[+\-*\/%^]/.test(trimmed) && !/\b(sqrt|sin|cos|abs)\b/i.test(trimmed))
            return null;

        // Whitelist allowed math tokens
        const validTokens = /^(?:[0-9]+(?:\.[0-9]+)?|0x[0-9a-fA-F]+|0b[01]+|\s+|[+\-*\/%(),]|\^|\*\*|\b(?:Math\.)?(?:sqrt|cbrt|sin|cos|tan|abs|round|floor|ceil|log|log2|log10|exp|pow|min|max|PI|E|pi|e)\b)+$/i;
        if (!validTokens.test(trimmed))
            return null;

        const sanitized = trimmed.replace(/\bpi\b/gi, "Math.PI").replace(/\be\b/g, "Math.E").replace(/\b(sqrt|cbrt|sin|cos|tan|abs|round|floor|ceil|log|log2|log10|exp|pow|min|max)\b/gi, "Math.$1").replace(/\^/g, "**");
        try {
            const val = Function('"use strict"; return (' + sanitized + ')')();
            if (typeof val === "number" && !isNaN(val) && isFinite(val)) {
                const formatted = Math.abs(val) < 1e+12 ? parseFloat(val.toFixed(6)).toString() : val.toExponential(4);
                return {
                    "type": "math",
                    "expression": trimmed,
                    "result": formatted
                };
            }
        } catch (e) {
            return null;
        }
        return null;
    }

    function inspectTimestamp(str) {
        if (!str || str.length < 10 || str.length > 13)
            return null;

        const trimmed = str.trim();
        if (!/^\d{10}(\d{3})?$/.test(trimmed))
            return null;

        const isMs = trimmed.length === 13;
        const num = parseInt(trimmed, 10);
        const ms = isMs ? num : num * 1000;
        // Check reasonable range between 2000-01-01 and 2050-01-01
        if (ms < 9.46685e+11 || ms > 2.52461e+12)
            return null;

        const d = new Date(ms);
        if (isNaN(d.getTime()))
            return null;

        const pad = (n) => {
            return n < 10 ? "0" + n : n.toString();
        };
        const year = d.getFullYear();
        const month = pad(d.getMonth() + 1);
        const day = pad(d.getDate());
        const hours = pad(d.getHours());
        const mins = pad(d.getMinutes());
        const secs = pad(d.getSeconds());
        const formatted = `${year}-${month}-${day} ${hours}:${mins}:${secs}`;
        const iso = d.toISOString();
        // Relative time calculation
        const now = Date.now();
        const diffSec = Math.round((now - ms) / 1000);
        let relative = "";
        const absDiff = Math.abs(diffSec);
        const suffix = diffSec >= 0 ? Translation.tr("ago") : Translation.tr("from now");
        if (absDiff < 60)
            relative = Translation.tr("just now");
        else if (absDiff < 3600)
            relative = `${Math.floor(absDiff / 60)} ${Translation.tr("min")}${suffix}`;
        else if (absDiff < 86400)
            relative = `${Math.floor(absDiff / 3600)} ${Translation.tr("hr")}${suffix}`;
        else
            relative = `${Math.floor(absDiff / 86400)} ${Translation.tr("day")}${suffix}`;
        return {
            "type": "timestamp",
            "timestamp": num,
            "formatted": formatted,
            "iso": iso,
            "relative": relative
        };
    }

    function inspectUrl(str) {
        if (!str || (!str.startsWith("http://") && !str.startsWith("https://")))
            return null;

        const trimmed = str.trim();
        // Check basic URL format without spaces
        if (/\s/.test(trimmed))
            return null;

        return {
            "type": "url",
            "url": trimmed
        };
    }

    function inspectPath(str) {
        if (!str || str.length < 2)
            return null;

        const trimmed = str.trim();
        if (trimmed.includes("\n") || trimmed.includes("\r"))
            return null;

        if (!trimmed.startsWith("/") && !trimmed.startsWith("~/") && !trimmed.startsWith("file://"))
            return null;

        let cleanPath = trimmed;
        if (cleanPath.startsWith("file://"))
            cleanPath = cleanPath.slice(7);

        if (cleanPath.startsWith("~/")) {
            const home = FileUtils.trimFileProtocol(Directories.home);
            cleanPath = home + cleanPath.slice(1);
        }
        const dir = FileUtils.parentDirectory(cleanPath);
        return {
            "type": "path",
            "raw": trimmed,
            "expanded": cleanPath,
            "directory": dir || cleanPath
        };
    }

    function inspectJson(str) {
        if (!str || str.length < 4 || str.length > 50000)
            return null;

        const trimmed = str.trim();
        if (!((trimmed.startsWith("{") && trimmed.endsWith("}")) || (trimmed.startsWith("[") && trimmed.endsWith("]"))))
            return null;

        try {
            const obj = JSON.parse(trimmed);
            if (typeof obj !== "object" || obj === null)
                return null;

            return {
                "type": "json",
                "pretty": JSON.stringify(obj, null, 2),
                "minified": JSON.stringify(obj)
            };
        } catch (e) {
            return null;
        }
    }

    function inspectBase64(str) {
        if (!str || str.length < 8 || str.length > 10000 || str.length % 4 !== 0)
            return null;

        const trimmed = str.trim();
        if (!/^[A-Za-z0-9+/]+={0,2}$/.test(trimmed))
            return null;

        // Don't treat simple short English words or digits as base64
        if (/^[a-zA-Z]+$/.test(trimmed) && trimmed.length < 12)
            return null;

        if (/^[0-9]+$/.test(trimmed))
            return null;

        try {
            const decoded = atob(trimmed);
            let printable = 0;
            for (let i = 0; i < decoded.length; i++) {
                const code = decoded.charCodeAt(i);
                if (code === 9 || code === 10 || code === 13 || (code >= 32 && code <= 126) || code > 127)
                    printable++;

            }
            if (printable / decoded.length > 0.85 && decoded.length >= 2)
                return {
                    "type": "base64",
                    "decoded": decoded
                };

        } catch (e) {
            return null;
        }
        return null;
    }

}
