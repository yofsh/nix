import QtQuick
import Quickshell.Io
import "../../components" as Components
import "../../config" as AppConfig

// Ping panel (graph + stats) for one target. The popup passes the target,
// mirrors its open state into popupOpen and sizes the panel externally.
Rectangle {
    id: panel

    property var target: ({ id: "", label: "", iconCode: 0xF059F, host: "" })
    property bool popupOpen: false
    property int pingMaxHistory: 80

    property int currentPing: -1   // -1 = pending, -2 = timeout
    property int avgPing: 0
    property int maxPing: 0
    property int packetCount: 0
    property int packetLoss: 0
    property var history: []

    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    function pingColorFor(val) {
        if (val < 0) return "#ef5350";
        if (val <= 30) return "#66bb6a";
        if (val <= 70) return "#ffb74d";
        if (val <= 120) return "#f4721a";
        return "#ef5350";
    }

    // Round a max-ping value up to the next "nice" axis ceiling so the
    // graph never clips and the user gets human-readable tick labels.
    function niceMax(v) {
        if (v <= 50)   return 50;
        if (v <= 100)  return 100;
        if (v <= 200)  return 200;
        if (v <= 300)  return 300;
        if (v <= 500)  return 500;
        if (v <= 750)  return 750;
        if (v <= 1000) return 1000;
        if (v <= 1500) return 1500;
        if (v <= 2000) return 2000;
        return Math.ceil(v / 1000) * 1000;
    }

    function appendSample(val) {
        var h = panel.history.slice();
        h.push(val);
        if (h.length > panel.pingMaxHistory) h.shift();
        panel.history = h;
        panel.packetCount += 1;
        if (val === -2) panel.packetLoss += 1;

        // Recompute average and max over valid samples
        var sum = 0, count = 0, mx = 0;
        for (var i = 0; i < h.length; i++) {
            if (h[i] >= 0) {
                sum += h[i];
                count += 1;
                if (h[i] > mx) mx = h[i];
            }
        }
        panel.avgPing = count > 0 ? Math.round(sum / count) : 0;
        panel.maxPing = mx;
        graph.requestPaint();
    }

    function parseLine(line) {
        // ping -O output: "no answer yet for icmp_seq=X"  or  "...time=12.3 ms"
        var m = line.match(/time=([\d.]+)\s*ms/);
        if (m) {
            panel.currentPing = Math.round(parseFloat(m[1]));
            appendSample(panel.currentPing);
        } else if (line.indexOf("no answer") >= 0
                || line.indexOf("Destination Host Unreachable") >= 0
                || line.indexOf("Request timeout") >= 0) {
            panel.currentPing = -2;
            appendSample(-2);
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4

        // Header
        Row {
            spacing: 6
            width: parent.width
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(panel.target.iconCode)
                font.pixelSize: 13
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.target.label
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                font.bold: true
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.target.host ? "  " + panel.target.host : ""
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            }
            Item { width: 1; height: 1 }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.currentPing === -2 ? "× timeout"
                    : (panel.currentPing < 0 ? "…" : panel.currentPing + " ms")
                color: panel.pingColorFor(panel.currentPing)
                font.bold: true
            }
        }

        // Graph
        Canvas {
            id: graph
            width: parent.width
            height: parent.height - 48

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var h = panel.history;
                if (h.length === 0) return;

                // Auto-scale: pick a nice ceiling at or above the
                // current max sample, but never below 100ms so a calm
                // line doesn't hug the bottom of the graph.
                var scaleMax = panel.niceMax(Math.max(100, panel.maxPing));

                // Horizontal grid at 25/50/75% of scale
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.07);
                ctx.lineWidth = 1;
                for (var g = 0.25; g <= 0.75; g += 0.25) {
                    var gy = height - g * height;
                    ctx.beginPath();
                    ctx.moveTo(0, gy);
                    ctx.lineTo(width, gy);
                    ctx.stroke();
                }

                var slot = width / panel.pingMaxHistory;
                var offset = width - h.length * slot;

                // Bars
                for (var i = 0; i < h.length; i++) {
                    var val = h[i];
                    var x = offset + i * slot;
                    if (val === -2) {
                        ctx.fillStyle = "#ef5350";
                        ctx.fillRect(x, 0, Math.max(1, slot), height);
                        continue;
                    }
                    if (val < 0) continue;
                    var clamped = Math.min(val, scaleMax);
                    var barH = (clamped / scaleMax) * height;
                    ctx.fillStyle = panel.pingColorFor(val);
                    ctx.fillRect(x, height - barH, Math.max(1, slot), barH);
                }

                // Y-axis tick labels (top + middle)
                ctx.fillStyle = "rgba(255,255,255,0.45)";
                ctx.font = "9px '" + AppConfig.Config.theme.fontFamily + "'";
                ctx.textAlign = "left";
                ctx.fillText(scaleMax + " ms", 2, 10);
                ctx.fillText(Math.round(scaleMax / 2) + " ms", 2, height / 2 - 2);
            }
        }

        // Footer stats
        Row {
            width: parent.width
            spacing: 12

            Column {
                spacing: -1
                Components.ThemedText {
                    text: "avg"
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
                Components.ThemedText {
                    text: panel.avgPing > 0 ? panel.avgPing + " ms" : "—"
                    color: panel.pingColorFor(panel.avgPing)
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    font.bold: true
                }
            }
            Column {
                spacing: -1
                Components.ThemedText {
                    text: "max"
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
                Components.ThemedText {
                    text: panel.maxPing > 0 ? panel.maxPing + " ms" : "—"
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
            }
            Column {
                spacing: -1
                Components.ThemedText {
                    text: "loss"
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
                Components.ThemedText {
                    text: panel.packetCount > 0
                        ? (panel.packetLoss * 100 / panel.packetCount).toFixed(1) + "%"
                        : "—"
                    color: panel.packetLoss === 0 ? "#66bb6a" : "#ef5350"
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    font.bold: panel.packetLoss > 0
                }
            }
        }
    }

    // Continuous ping pipe — one process per target, no per-tick spawn.
    // -O surfaces missing replies; -W is per-reply timeout; -i 0.5 = 500ms.
    Process {
        id: pingProc
        command: ["ping", "-O", "-W", "3", "-i", "0.333", panel.target.host]
        running: panel.popupOpen && panel.target.host !== ""
        // Restart if it dies unexpectedly while popup is still open
        onRunningChanged: {
            if (!running && panel.popupOpen && panel.target.host !== "")
                running = true;
        }
        stdout: SplitParser {
            onRead: data => panel.parseLine(data)
        }
    }

    // Clear history when popup closes so the next open starts fresh.
    Connections {
        target: panel
        function onPopupOpenChanged() {
            if (!panel.popupOpen) {
                panel.history = [];
                panel.currentPing = -1;
                panel.avgPing = 0;
                panel.maxPing = 0;
                panel.packetCount = 0;
                panel.packetLoss = 0;
                graph.requestPaint();
            }
        }
    }
}
