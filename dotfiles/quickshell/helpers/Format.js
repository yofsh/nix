.pragma library

// Canonical formatting helpers shared by all widgets/popups.
// Import with:  import "../../helpers/Format.js" as Format

// 1536 -> "1.5 KB", 3221225472 -> "3.0 GB"
function bytes(b) {
    if (!b || b < 1024)
        return (Math.round(b) || 0) + " B";
    if (b < 1048576)
        return (b / 1024).toFixed(1) + " KB";
    if (b < 1073741824)
        return (b / 1048576).toFixed(1) + " MB";
    return (b / 1073741824).toFixed(1) + " GB";
}

// bytes per second -> "1.5 KB/s"
function rate(bytesPerSec) {
    if (!bytesPerSec || bytesPerSec < 1024)
        return (Math.round(bytesPerSec) || 0) + " B/s";
    if (bytesPerSec < 1048576)
        return (bytesPerSec / 1024).toFixed(1) + " KB/s";
    if (bytesPerSec < 1073741824)
        return (bytesPerSec / 1048576).toFixed(1) + " MB/s";
    return (bytesPerSec / 1073741824).toFixed(1) + " GB/s";
}

// 5025 -> "1h23m", 540 -> "9m"
function hoursMinutes(seconds) {
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    if (h > 0)
        return h + "h" + (m > 0 ? m + "m" : "");
    return m + "m";
}

// 95 -> "1:35" (m:ss countdown style)
function clock(seconds) {
    var m = Math.floor(seconds / 60);
    var s = Math.floor(seconds % 60);
    return m + ":" + (s < 10 ? "0" : "") + s;
}

// 5400 -> "1:30" (h:mm, e.g. battery time remaining)
function hourClock(seconds) {
    var h = Math.floor(seconds / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    return h + ":" + (m < 10 ? "0" : "") + m;
}

// 1234567 -> "1.2M", 45200 -> "45k"
function tokens(t) {
    if (!t)
        return "0";
    if (t >= 1e6)
        return (t / 1e6).toFixed(1) + "M";
    if (t >= 1e3)
        return Math.round(t / 1e3) + "k";
    return "" + t;
}

// 123.4 -> "$123", 12.34 -> "$12.3", 1.234 -> "$1.23"
function cost(c) {
    if (!c)
        return "$0";
    if (c >= 100)
        return "$" + Math.round(c);
    if (c >= 10)
        return "$" + c.toFixed(1);
    return "$" + c.toFixed(2);
}

// smart-precision percent value (no % sign): 42.31 -> "42", 4.27 -> "4.3"
function pct(v) {
    if (v >= 10)
        return Math.round(v).toString();
    if (v > 0)
        return v.toFixed(1);
    return "0";
}

// epoch ms -> "now" / "5m" / "2h" / "3d"
function timeAgo(epochMs, nowMs) {
    var now = nowMs !== undefined ? nowMs : Date.now();
    var s = Math.max(0, Math.floor((now - epochMs) / 1000));
    if (s < 60)
        return "now";
    if (s < 3600)
        return Math.floor(s / 60) + "m";
    if (s < 86400)
        return Math.floor(s / 3600) + "h";
    return Math.floor(s / 86400) + "d";
}
