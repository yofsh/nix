import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../helpers" as Helpers

PanelWindow {
    id: root
    property int barHeight: 22
    property bool popupOpen: false

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: 1260
    implicitHeight: 180
    visible: popupOpen || slideAnim.running
    color: "transparent"

    property var historyData: []   // [{time, pct, state}]
    property bool dataLoaded: false
    property string onBatteryText: ""
    property real hoverX: -1       // mouse X in canvas coords, -1 = not hovering
    property int hoverIdx: -1      // nearest data point index

    onPopupOpenChanged: {
        if (popupOpen) {
            loadProc.running = true;
        }
    }

    // Find and read the UPower charge history file (skip generic_id)
    Process {
        id: loadProc
        command: ["bash", "-c", "f=$(ls /var/lib/upower/history-charge-*.dat 2>/dev/null | grep -v generic_id | head -1); [ -f \"$f\" ] && cat \"$f\" || echo ''"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseHistory(this.text);
            }
        }
    }

    function parseHistory(raw) {
        var lines = raw.trim().split("\n");
        var data = [];
        var now = Date.now() / 1000;
        var cutoff = now - 259200; // last 3 days
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("\t");
            if (parts.length < 3) continue;
            var ts = parseFloat(parts[0]);
            var pct = parseFloat(parts[1]);
            var state = parts[2];
            if (pct <= 0 && state === "unknown") continue;
            if (ts < cutoff) continue;
            data.push({time: ts, pct: pct, state: state});
        }
        historyData = data;
        dataLoaded = true;

        // Calculate time on battery since last charge (last 90%+ entry)
        var gapThreshold = 1800; // 30min — skip gaps where system was off
        // Find last 90%+ entry, then find the peak in that charge session
        var startIdx = -1;
        for (var j = data.length - 1; j >= 0; j--) {
            if (data[j].pct >= 90) {
                startIdx = j;
                break;
            }
        }
        // Scan backwards from startIdx to find the actual peak
        var peakIdx = startIdx;
        if (startIdx >= 0) {
            for (var p = startIdx - 1; p >= 0; p--) {
                if (data[p].pct > data[peakIdx].pct)
                    peakIdx = p;
                if (data[p].pct < 90) break; // left the charge session
            }
            startIdx = peakIdx;
        }
        var secs = 0;
        if (startIdx >= 0) {
            for (var k = startIdx; k < data.length - 1; k++) {
                if (data[k].state !== "discharging") continue;
                var dt = data[k+1].time - data[k].time;
                if (dt > 0 && dt < gapThreshold)
                    secs += dt;
            }
        }
        if (startIdx >= 0 && secs > 0) {
            var hh = Math.floor(secs / 3600);
            var mm = Math.floor((secs % 3600) / 60);
            var chargeEntry = data[startIdx];
            var d = new Date(chargeEntry.time * 1000);
            var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
            var day = days[d.getDay()];
            var ch = d.getHours();
            var cm = d.getMinutes();
            var timeStr = day + " " + (ch < 10 ? "0" : "") + ch + ":" + (cm < 10 ? "0" : "") + cm;
            onBatteryText = hh + "h" + (mm < 10 ? "0" : "") + mm + "m on battery  \u2014  last charge " + Math.round(chargeEntry.pct) + "% at " + timeStr;
        } else {
            onBatteryText = "";
        }

        graphCanvas.requestPaint();
    }

    // Refresh every 5 minutes while open
    Timer {
        interval: 300000
        running: root.popupOpen
        repeat: true
        onTriggered: loadProc.running = true
    }

    Item {
        anchors.fill: parent
        clip: true

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            y: -parent.height
            opacity: 0.85

            states: State {
                name: "visible"; when: root.popupOpen
                PropertyChanges { target: popupContent; y: 0 }
            }

            transitions: Transition {
                id: slideAnim
                NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic }
            }

            Item {
                anchors.fill: parent
                clip: true
                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: -16
                    color: "#11000000"
                    radius: 16
                }
            }

            // Header
            Text {
                id: headerText
                anchors.top: parent.top
                anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                text: {
                    if (!root.dataLoaded || root.historyData.length === 0) return "Battery History";
                    var last = root.historyData[root.historyData.length - 1];
                    var stateText = last.state === "charging" ? " charging" :
                                   last.state === "fully-charged" ? " full" : "";
                    return Math.round(last.pct) + "%" + stateText + "  \u2014  last 3 days";
                }
                color: Helpers.Colors.battery
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 11
            }

            // On-battery time
            Text {
                id: onBatteryLabel
                anchors.top: headerText.bottom
                anchors.topMargin: 1
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.onBatteryText
                visible: root.onBatteryText !== ""
                color: Helpers.Colors.textMuted
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 9
            }

            // Graph
            Canvas {
                id: graphCanvas
                anchors.top: onBatteryLabel.visible ? onBatteryLabel.bottom : headerText.bottom
                anchors.topMargin: 3
                anchors.left: parent.left
                anchors.leftMargin: 36
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);

                    var d = root.historyData;
                    if (d.length < 2) {
                        ctx.fillStyle = Helpers.Colors.textMuted;
                        ctx.font = "11px 'DejaVuSansM Nerd Font'";
                        ctx.textAlign = "center";
                        ctx.fillText("no data", width / 2, height / 2);
                        return;
                    }

                    var w = width;
                    var h = height;
                    var now = Date.now() / 1000;
                    var tMin = now - 259200; // fixed 3-day window
                    var tMax = now;
                    var tRange = tMax - tMin;

                    // Grid lines
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.07);
                    ctx.lineWidth = 1;
                    for (var g = 25; g <= 75; g += 25) {
                        var gy = h - (g / 100) * h;
                        ctx.beginPath();
                        ctx.moveTo(0, gy);
                        ctx.lineTo(w, gy);
                        ctx.stroke();
                    }

                    // Draw filled areas as contiguous paths grouped by state
                    // Gap threshold: >30min between records means system was off
                    var gapThreshold = 1800;
                    var smallW = Math.max(1, w / tRange * 120); // ~2min cap

                    function stateColor(state) {
                        if (state === "charging") return "" + Helpers.Colors.batteryCharging;
                        if (state === "fully-charged") return "#a6e3a1";
                        return "" + Helpers.Colors.battery;
                    }

                    // Build segments: contiguous + same state
                    var segments = []; // [{start, end, color}]
                    var i = 0;
                    while (i < d.length) {
                        var color = stateColor(d[i].state);
                        var start = i;
                        while (i < d.length - 1
                               && (d[i+1].time - d[i].time) < gapThreshold
                               && stateColor(d[i+1].state) === color) {
                            i++;
                        }
                        segments.push({start: start, end: i, color: color});
                        i++;
                    }

                    // Draw each segment as a single filled path
                    for (var s = 0; s < segments.length; s++) {
                        var seg = segments[s];
                        ctx.beginPath();

                        var x0 = ((d[seg.start].time - tMin) / tRange) * w;
                        ctx.moveTo(x0, h);

                        for (var j = seg.start; j <= seg.end; j++) {
                            var x = ((d[j].time - tMin) / tRange) * w;
                            var y = h - (d[j].pct / 100) * h;
                            ctx.lineTo(x, y);
                            if (j < seg.end) {
                                var xNext = ((d[j+1].time - tMin) / tRange) * w;
                                ctx.lineTo(xNext, y);
                            }
                        }

                        // Cap the right edge
                        var xLast = ((d[seg.end].time - tMin) / tRange) * w;
                        var yLast = h - (d[seg.end].pct / 100) * h;
                        // If next segment is contiguous (just different state), extend to its start
                        var xRight;
                        if (seg.end + 1 < d.length && (d[seg.end + 1].time - d[seg.end].time) < gapThreshold) {
                            xRight = ((d[seg.end + 1].time - tMin) / tRange) * w;
                        } else {
                            xRight = xLast + smallW;
                        }
                        ctx.lineTo(xRight, yLast);
                        ctx.lineTo(xRight, h);
                        ctx.closePath();

                        ctx.fillStyle = seg.color;
                        ctx.fill();
                    }

                    // Hover crosshair + tooltip
                    if (root.hoverIdx >= 0 && root.hoverIdx < d.length) {
                        var hi = root.hoverIdx;
                        var hx = ((d[hi].time - tMin) / tRange) * w;
                        var hy = h - (d[hi].pct / 100) * h;

                        // Vertical line
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.3);
                        ctx.lineWidth = 1;
                        ctx.beginPath();
                        ctx.moveTo(hx, 0);
                        ctx.lineTo(hx, h);
                        ctx.stroke();

                        // Dot
                        ctx.beginPath();
                        ctx.arc(hx, hy, 3, 0, 2 * Math.PI);
                        ctx.fillStyle = "white";
                        ctx.fill();

                        // Tooltip text
                        var hDate = new Date(d[hi].time * 1000);
                        var hDays = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                        var hDay = hDays[hDate.getDay()];
                        var hHH = hDate.getHours();
                        var hMM = hDate.getMinutes();
                        var hTime = hDay + " " + (hHH < 10 ? "0" : "") + hHH + ":" + (hMM < 10 ? "0" : "") + hMM;
                        var hState = d[hi].state === "charging" ? " \u25B2" :
                                     d[hi].state === "fully-charged" ? " \u2713" : "";
                        var label = Math.round(d[hi].pct) + "%" + hState + "  " + hTime;

                        ctx.font = "10px 'DejaVuSansM Nerd Font'";
                        var tw = ctx.measureText(label).width;
                        var tx = hx + 8;
                        if (tx + tw + 8 > w) tx = hx - tw - 16;
                        var ty = Math.max(16, hy - 4);

                        // Background
                        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.7);
                        ctx.fillRect(tx - 4, ty - 12, tw + 8, 16);
                        // Text
                        ctx.fillStyle = "white";
                        ctx.textAlign = "left";
                        ctx.fillText(label, tx, ty);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onPositionChanged: function(mouse) {
                        var d = root.historyData;
                        if (d.length === 0) return;
                        var now = Date.now() / 1000;
                        var tMin = now - 259200;
                        var tRange = 259200;
                        // Convert mouse X to timestamp
                        var t = tMin + (mouse.x / parent.width) * tRange;
                        // Binary search for nearest point
                        var lo = 0, hi = d.length - 1;
                        while (lo < hi) {
                            var mid = (lo + hi) >> 1;
                            if (d[mid].time < t) lo = mid + 1;
                            else hi = mid;
                        }
                        // Check lo and lo-1 for closest
                        if (lo > 0 && Math.abs(d[lo-1].time - t) < Math.abs(d[lo].time - t))
                            lo = lo - 1;
                        root.hoverIdx = lo;
                        root.hoverX = mouse.x;
                        graphCanvas.requestPaint();
                    }
                    onExited: {
                        root.hoverIdx = -1;
                        root.hoverX = -1;
                        graphCanvas.requestPaint();
                    }
                }
            }

            // Y-axis labels
            Repeater {
                model: [0, 25, 50, 75, 100]
                Text {
                    required property int modelData
                    x: 6
                    y: graphCanvas.y + graphCanvas.height - (modelData / 100) * graphCanvas.height - 5
                    text: modelData
                    color: Helpers.Colors.textMuted
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 8
                }
            }

            // X-axis time labels
            Repeater {
                model: root.timeLabels
                Text {
                    required property var modelData
                    x: graphCanvas.x + modelData.x - implicitWidth / 2
                    y: graphCanvas.y + graphCanvas.height + 3
                    text: modelData.label
                    color: Helpers.Colors.textMuted
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 8
                }
            }
        }
    }

    property var timeLabels: {
        if (historyData.length < 2) return [];
        var w = graphCanvas.width;
        if (w <= 0) return [];
        var now = Date.now() / 1000;
        var tMin = now - 259200;
        var tRange = 259200;

        // Place ~6 evenly spaced labels
        var labels = [];
        var count = 6;
        var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
        for (var i = 0; i <= count; i++) {
            var t = tMin + (tRange * i / count);
            var date = new Date(t * 1000);
            var hh = date.getHours();
            var mm = date.getMinutes();
            var day = days[date.getDay()];
            var label = day + " " + (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm;
            labels.push({x: (i / count) * w, label: label});
        }
        return labels;
    }
}
