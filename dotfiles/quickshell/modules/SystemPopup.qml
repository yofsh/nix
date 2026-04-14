import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../helpers" as Helpers
import "../components" as Components
import "../config" as AppConfig

PanelWindow {
    id: root
    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: 1260
    implicitHeight: 560
    visible: popupOpen
    color: "transparent"

    property var statsData: []
    property string ifaceName: ""
    property string loadAvg: ""
    property real uptimeSecs: 0
    property real totalMemKB: 0
    property bool dataLoaded: false
    property int hoverIdx: -1
    property string hoverGraph: ""
    property real netMax: 1
    property real ioMax: 1
    property real loadMax: 1
    property real psiMax: 1

    property real timeframeSecs: 259200  // default 3d
    readonly property var timeframes: [
        {label: "3h",  secs: 10800},
        {label: "6h",  secs: 21600},
        {label: "12h", secs: 43200},
        {label: "1d",  secs: 86400},
        {label: "3d",  secs: 259200},
        {label: "7d",  secs: 604800}
    ]

    onTimeframeSecsChanged: { recomputeScales(); repaintAll(); }

    readonly property real graphLeftMargin: 48
    readonly property real graphRightMargin: 12
    readonly property int gapThreshold: 1800
    readonly property real graphSpacing: 2
    readonly property real headerHeight: 22
    readonly property real xAxisHeight: 16
    readonly property real labelHeight: 12

    readonly property real graphHeight: Math.max(30,
        (implicitHeight - headerHeight - xAxisHeight - (graphSpacing + labelHeight) * 5 - 4) / 5)

    onPopupOpenChanged: {
        if (popupOpen) loadProc.running = true;
    }

    Process {
        id: loadProc
        command: ["bash", "-c", [
            "SADF=$(systemctl cat sysstat-collect.service 2>/dev/null | grep -oP '/nix/store/\\S+/lib/sa/sa1' | head -1 | sed 's|/lib/sa/sa1||')/bin/sadf",
            "IFACE=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \\K\\S+')",
            "LOAD=$(cat /proc/loadavg | cut -d' ' -f1-3)",
            "UPTIME=$(awk '{print $1}' /proc/uptime)",
            "all=''",
            "for i in 6 5 4 3 2 1 0; do",
            "  d=$(date -d \"$i days ago\" +%d)",
            "  f=\"/var/log/sa/sa${d}\"",
            "  [ -f \"$f\" ] || continue",
            "  json=$(LANG=C $SADF -j \"$f\" -- -u -r -S -n DEV -b -q ALL 2>/dev/null)",
            "  [ -z \"$json\" ] && continue",
            "  stats=$(echo \"$json\" | jq -c --arg iface \"$IFACE\" '[.sysstat.hosts[0].statistics[] | {t: .timestamp.date + \"T\" + .timestamp.time + \"Z\", cpu: (.\"cpu-load\"[0] | {u: .user, s: .system, w: .iowait}), mem: (.memory | {p: .\"memused-percent\", u: .memused, a: .avail, c: .cached, sp: .\"swpused-percent\"}), net: (.network.\"net-dev\"[] | select(.iface == $iface) | {r: .rxkB, t: .txkB}), io: (.io | {r: (.\"io-reads\".bread / 2), w: (.\"io-writes\".bwrtn / 2)}), load: (.queue | {l1: .\"ldavg-1\", l5: .\"ldavg-5\", l15: .\"ldavg-15\"}), psi: (.psi | {c: .\"psi-cpu\".some_avg300, i: .\"psi-io\".some_avg300, m: .\"psi-mem\".some_avg300})}]')",
            "  if [ -z \"$all\" ]; then all=\"$stats\"",
            "  else all=$(echo \"$all $stats\" | jq -sc '.[0] + .[1]')",
            "  fi",
            "done",
            "echo \"{\\\"iface\\\":\\\"$IFACE\\\",\\\"load\\\":\\\"$LOAD\\\",\\\"uptime\\\":$UPTIME,\\\"stats\\\":${all:-[]}}\""
        ].join("\n")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseData(this.text)
        }
    }

    function parseData(raw) {
        try {
            var data = JSON.parse(raw);
            root.ifaceName = data.iface || "";
            root.loadAvg = data.load || "";
            root.uptimeSecs = data.uptime || 0;

            var stats = data.stats || [];
            var parsed = [];
            for (var i = 0; i < stats.length; i++) {
                var s = stats[i];
                var d = new Date(s.t);
                parsed.push({
                    t: d.getTime() / 1000,
                    cpu: s.cpu || {u: 0, s: 0, w: 0},
                    mem: s.mem || {p: 0, u: 0, a: 0, c: 0, sp: 0},
                    net: s.net || {r: 0, t: 0},
                    io: s.io || {r: 0, w: 0},
                    load: s.load || {l1: 0, l5: 0, l15: 0},
                    psi: s.psi || {c: 0, i: 0, m: 0}
                });
            }
            root.statsData = parsed;
            root.dataLoaded = parsed.length > 0;

            if (parsed.length > 0) {
                var last = parsed[parsed.length - 1];
                root.totalMemKB = last.mem.u + last.mem.a;
            }

            recomputeScales();
            repaintAll();
        } catch (e) {
            console.warn("SystemPopup parse error:", e);
        }
    }

    function recomputeScales() {
        var tr = timeRange();
        var netVals = [], ioVals = [], loadVals = [], psiVals = [];
        for (var j = 0; j < statsData.length; j++) {
            var p = statsData[j];
            if (p.t < tr.min) continue;
            netVals.push(p.net.r, p.net.t);
            ioVals.push(p.io.r, p.io.w);
            loadVals.push(p.load.l1);
            psiVals.push(p.psi.c, p.psi.i, p.psi.m);
        }
        root.netMax = Math.max(p95(netVals) * 1.1, 1);
        root.ioMax = Math.max(p95(ioVals) * 1.1, 1);
        root.loadMax = Math.max(p95(loadVals) * 1.2, 0.5);
        root.psiMax = Math.max(p95(psiVals) * 1.2, 0.5);
    }

    function p95(arr) {
        if (arr.length === 0) return 0;
        arr.sort(function(a, b) { return a - b; });
        return arr[Math.min(Math.floor(arr.length * 0.95), arr.length - 1)] || 0;
    }

    function timeRange() {
        var now = Date.now() / 1000;
        var range = root.timeframeSecs;
        return {min: now - range, max: now, range: range};
    }

    function xForTime(t, w) {
        var tr = timeRange();
        return ((t - tr.min) / tr.range) * w;
    }

    function findNearest(mouseX, canvasW) {
        var d = root.statsData;
        if (d.length === 0) return -1;
        var tr = timeRange();
        var t = tr.min + (mouseX / canvasW) * tr.range;
        var lo = 0, hi = d.length - 1;
        while (lo < hi) {
            var mid = (lo + hi) >> 1;
            if (d[mid].t < t) lo = mid + 1;
            else hi = mid;
        }
        if (lo > 0 && Math.abs(d[lo - 1].t - t) < Math.abs(d[lo].t - t))
            lo = lo - 1;
        return lo;
    }

    function formatKB(kb) {
        if (kb >= 1048576) return (kb / 1048576).toFixed(1) + " GB";
        if (kb >= 1024) return (kb / 1024).toFixed(1) + " MB";
        return Math.round(kb) + " KB";
    }

    function formatRate(kbps) {
        if (kbps >= 1024) return (kbps / 1024).toFixed(1) + " MB/s";
        return kbps.toFixed(1) + " KB/s";
    }

    function formatUptime(secs) {
        var days = Math.floor(secs / 86400);
        var hrs = Math.floor((secs % 86400) / 3600);
        var mins = Math.floor((secs % 3600) / 60);
        if (days > 0) return days + "d " + hrs + "h";
        return hrs + "h " + mins + "m";
    }

    function drawGrid(ctx, w, h) {
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.07);
        ctx.lineWidth = 1;
        for (var g = 25; g <= 75; g += 25) {
            var gy = h - (g / 100) * h;
            ctx.beginPath();
            ctx.moveTo(0, gy);
            ctx.lineTo(w, gy);
            ctx.stroke();
        }
    }

    function drawHoverLine(ctx, w, h) {
        if (root.hoverIdx < 0 || root.hoverIdx >= root.statsData.length) return;
        var hx = xForTime(root.statsData[root.hoverIdx].t, w);
        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.3);
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(hx, 0);
        ctx.lineTo(hx, h);
        ctx.stroke();
    }

    function drawStepArea(ctx, w, h, getData, color) {
        var d = root.statsData;
        if (d.length < 2) return;

        var segments = buildSegments(d);
        ctx.fillStyle = color;
        for (var s = 0; s < segments.length; s++) {
            var seg = segments[s];
            if (seg.start === seg.end) continue;
            ctx.beginPath();
            ctx.moveTo(xForTime(d[seg.start].t, w), h);
            for (var j = seg.start; j <= seg.end; j++) {
                var x = xForTime(d[j].t, w);
                var y = h - (getData(d[j]) / 100) * h;
                ctx.lineTo(x, y);
                if (j < seg.end) ctx.lineTo(xForTime(d[j + 1].t, w), y);
            }
            var xL = xForTime(d[seg.end].t, w);
            ctx.lineTo(xL + 2, h - (getData(d[seg.end]) / 100) * h);
            ctx.lineTo(xL + 2, h);
            ctx.closePath();
            ctx.fill();
        }
    }

    // Step area scaled to a custom max value instead of percentage
    function drawStepAreaScaled(ctx, w, h, maxVal, getData, color) {
        var d = root.statsData;
        if (d.length < 2) return;

        var segments = buildSegments(d);
        ctx.fillStyle = color;
        for (var s = 0; s < segments.length; s++) {
            var seg = segments[s];
            if (seg.start === seg.end) continue;
            ctx.beginPath();
            ctx.moveTo(xForTime(d[seg.start].t, w), h);
            for (var j = seg.start; j <= seg.end; j++) {
                var x = xForTime(d[j].t, w);
                var val = Math.min(getData(d[j]), maxVal);
                var y = h - (val / maxVal) * h;
                ctx.lineTo(x, y);
                if (j < seg.end) ctx.lineTo(xForTime(d[j + 1].t, w), y);
            }
            var xL = xForTime(d[seg.end].t, w);
            ctx.lineTo(xL + 2, h - (Math.min(getData(d[seg.end]), maxVal) / maxVal) * h);
            ctx.lineTo(xL + 2, h);
            ctx.closePath();
            ctx.fill();
        }
    }

    function buildSegments(d) {
        var segments = [];
        var segStart = 0;
        for (var i = 1; i < d.length; i++) {
            if ((d[i].t - d[i - 1].t) > root.gapThreshold) {
                segments.push({start: segStart, end: i - 1});
                segStart = i;
            }
        }
        segments.push({start: segStart, end: d.length - 1});
        return segments;
    }

    function drawTooltip(ctx, w, h, graphName) {
        if (root.hoverIdx < 0 || root.hoverIdx >= root.statsData.length) return;
        if (root.hoverGraph !== graphName) return;

        var p = root.statsData[root.hoverIdx];
        var hx = xForTime(p.t, w);

        // Dot position depends on graph
        var dotY;
        if (graphName === "cpu") dotY = h - ((p.cpu.u + p.cpu.s + p.cpu.w) / 100) * h;
        else if (graphName === "mem") dotY = h - (p.mem.p / 100) * h;
        else if (graphName === "io") dotY = h - (Math.min(p.io.r, root.ioMax) / root.ioMax) * h;
        else if (graphName === "net") dotY = h - (Math.min(p.net.r, root.netMax) / root.netMax) * h;
        else dotY = h - (Math.min(p.load.l1, root.loadMax) / root.loadMax) * h;

        ctx.beginPath();
        ctx.arc(hx, dotY, 3, 0, 2 * Math.PI);
        ctx.fillStyle = "white";
        ctx.fill();

        // Tooltip lines
        var d = new Date(p.t * 1000);
        var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
        var hh = d.getHours();
        var mm = d.getMinutes();
        var timeStr = dayNames[d.getDay()] + " " + (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm;

        var lines = [];
        var colors = [];

        lines.push("CPU " + p.cpu.u.toFixed(1) + "% usr  " + p.cpu.s.toFixed(1) + "% sys  " + p.cpu.w.toFixed(1) + "% io");
        colors.push("" + Helpers.Colors.cpu);

        lines.push("Mem " + p.mem.p.toFixed(1) + "%  Swap " + p.mem.sp.toFixed(1) + "%");
        colors.push("" + Helpers.Colors.memory);

        lines.push("Disk \u2193" + root.formatRate(p.io.r) + "  \u2191" + root.formatRate(p.io.w));
        colors.push("#b39ddb");

        lines.push("Net \u2193" + root.formatRate(p.net.r) + "  \u2191" + root.formatRate(p.net.t));
        colors.push("#42a5f5");

        lines.push("Load " + p.load.l1.toFixed(2) + " / " + p.load.l5.toFixed(2) + " / " + p.load.l15.toFixed(2));
        colors.push("#ffb74d");

        var psiTotal = p.psi.c + p.psi.i + p.psi.m;
        if (psiTotal > 0.01)
            lines.push("PSI  cpu " + p.psi.c.toFixed(1) + "%  io " + p.psi.i.toFixed(1) + "%  mem " + p.psi.m.toFixed(1) + "%");
        else
            lines.push("PSI  none");
        colors.push("#ef5350");

        lines.push(timeStr);
        colors.push("rgba(255,255,255,0.4)");

        ctx.font = "10px '" + AppConfig.Config.theme.fontFamily + "'";
        var tw = 0;
        for (var il = 0; il < lines.length; il++) {
            var lw = ctx.measureText(lines[il]).width;
            if (lw > tw) tw = lw;
        }

        var tooltipX = hx + 10;
        if (tooltipX + tw + 12 > w) tooltipX = hx - tw - 20;
        var boxH = 12 * lines.length + 6;
        var tooltipY = Math.max(6, Math.min(dotY - 24, h - boxH - 6));

        var boxW = tw + 12;
        var boxR = 4;
        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.8);
        ctx.beginPath();
        ctx.moveTo(tooltipX + boxR, tooltipY);
        ctx.lineTo(tooltipX + boxW - boxR, tooltipY);
        ctx.quadraticCurveTo(tooltipX + boxW, tooltipY, tooltipX + boxW, tooltipY + boxR);
        ctx.lineTo(tooltipX + boxW, tooltipY + boxH - boxR);
        ctx.quadraticCurveTo(tooltipX + boxW, tooltipY + boxH, tooltipX + boxW - boxR, tooltipY + boxH);
        ctx.lineTo(tooltipX + boxR, tooltipY + boxH);
        ctx.quadraticCurveTo(tooltipX, tooltipY + boxH, tooltipX, tooltipY + boxH - boxR);
        ctx.lineTo(tooltipX, tooltipY + boxR);
        ctx.quadraticCurveTo(tooltipX, tooltipY, tooltipX + boxR, tooltipY);
        ctx.closePath();
        ctx.fill();

        ctx.textAlign = "left";
        for (var it = 0; it < lines.length; it++) {
            ctx.font = it === 0 ? "bold 10px '" + AppConfig.Config.theme.fontFamily + "'" : "10px '" + AppConfig.Config.theme.fontFamily + "'";
            ctx.fillStyle = colors[it];
            ctx.fillText(lines[it], tooltipX + 6, tooltipY + 13 + it * 12);
        }
    }

    function repaintAll() {
        cpuCanvas.requestPaint();
        memCanvas.requestPaint();
        ioCanvas.requestPaint();
        netCanvas.requestPaint();
        loadCanvas.requestPaint();
    }

    function onHover(graphName, mouseX, canvasW) {
        root.hoverGraph = graphName;
        root.hoverIdx = root.findNearest(mouseX, canvasW);
        root.repaintAll();
    }

    function onHoverExit() {
        root.hoverIdx = -1;
        root.hoverGraph = "";
        root.repaintAll();
    }

    Item {
        anchors.fill: parent

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface { anchors.fill: parent }

            // Header
            Row {
                id: headerRow
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.left: parent.left
                anchors.leftMargin: root.graphLeftMargin
                height: root.headerHeight
                spacing: 20

                Text {
                    text: {
                        if (!root.dataLoaded) return "System Stats";
                        var last = root.statsData[root.statsData.length - 1];
                        return "CPU " + last.cpu.u.toFixed(1) + "% usr  " + last.cpu.s.toFixed(1) + "% sys";
                    }
                    color: Helpers.Colors.cpu
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: root.loadAvg ? "Load " + root.loadAvg : ""
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: {
                        if (!root.dataLoaded) return "";
                        var last = root.statsData[root.statsData.length - 1];
                        return "Mem " + last.mem.p.toFixed(0) + "%  (" + root.formatKB(last.mem.u) + " / " + root.formatKB(root.totalMemKB) + ")";
                    }
                    color: Helpers.Colors.memory
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: {
                        var parts = [];
                        if (root.ifaceName) parts.push(root.ifaceName);
                        if (root.uptimeSecs > 0) parts.push("up " + root.formatUptime(root.uptimeSecs));
                        return parts.join("  ");
                    }
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Timeframe toggles
            Row {
                id: timeframeRow
                anchors.top: parent.top
                anchors.topMargin: 2
                anchors.right: parent.right
                anchors.rightMargin: root.graphRightMargin
                height: root.headerHeight
                spacing: 2

                Repeater {
                    model: root.timeframes
                    Rectangle {
                        required property var modelData
                        width: tfText.implicitWidth + 10
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 3
                        color: root.timeframeSecs === modelData.secs ? Qt.rgba(1, 1, 1, 0.15) : "transparent"

                        Text {
                            id: tfText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.timeframeSecs === modelData.secs ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeXSmall
                            font.bold: root.timeframeSecs === modelData.secs
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.timeframeSecs = modelData.secs
                        }
                    }
                }
            }

            // ──── CPU ────
            Text {
                id: cpuLabel
                anchors.top: headerRow.bottom
                anchors.left: parent.left; anchors.leftMargin: 6
                text: "CPU"; color: Helpers.Colors.cpu
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            Canvas {
                id: cpuCanvas
                anchors.top: cpuLabel.bottom
                anchors.left: parent.left; anchors.leftMargin: root.graphLeftMargin
                anchors.right: parent.right; anchors.rightMargin: root.graphRightMargin
                height: root.graphHeight

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (root.statsData.length < 2) {
                        ctx.fillStyle = Helpers.Colors.textMuted;
                        ctx.font = AppConfig.Config.theme.fontSizeBody + "px '" + AppConfig.Config.theme.fontFamily + "'";
                        ctx.textAlign = "center";
                        ctx.fillText("no data", width / 2, height / 2);
                        return;
                    }
                    root.drawGrid(ctx, width, height);
                    root.drawStepArea(ctx, width, height, function(p) { return p.cpu.w; }, Qt.rgba(0.90, 0.22, 0.21, 0.7));
                    root.drawStepArea(ctx, width, height, function(p) { return p.cpu.w + p.cpu.s; }, Qt.rgba(1, 0.60, 0, 0.7));
                    root.drawStepArea(ctx, width, height, function(p) { return p.cpu.w + p.cpu.s + p.cpu.u; }, Qt.rgba(0.30, 0.69, 0.31, 0.6));
                    root.drawHoverLine(ctx, width, height);
                    root.drawTooltip(ctx, width, height, "cpu");
                }

                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: function(mouse) { root.onHover("cpu", mouse.x, parent.width); }
                    onExited: root.onHoverExit()
                }
            }

            Text {
                x: 6; y: cpuCanvas.y + cpuCanvas.height * 0.5 - 5
                text: "50%"; color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            // ──── Memory + Swap ────
            Text {
                id: memLabel
                anchors.top: cpuCanvas.bottom; anchors.topMargin: root.graphSpacing
                anchors.left: parent.left; anchors.leftMargin: 6
                text: "Mem"; color: Helpers.Colors.memory
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            Canvas {
                id: memCanvas
                anchors.top: memLabel.bottom
                anchors.left: parent.left; anchors.leftMargin: root.graphLeftMargin
                anchors.right: parent.right; anchors.rightMargin: root.graphRightMargin
                height: root.graphHeight

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (root.statsData.length < 2) return;
                    root.drawGrid(ctx, width, height);
                    // Memory used %
                    root.drawStepArea(ctx, width, height, function(p) { return p.mem.p; }, Qt.rgba(0.50, 0.78, 0.51, 0.6));
                    // Swap used % overlaid
                    root.drawStepArea(ctx, width, height, function(p) { return p.mem.sp; }, Qt.rgba(1.0, 0.65, 0.0, 0.7));
                    root.drawHoverLine(ctx, width, height);
                    root.drawTooltip(ctx, width, height, "mem");
                }

                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: function(mouse) { root.onHover("mem", mouse.x, parent.width); }
                    onExited: root.onHoverExit()
                }
            }

            Text {
                x: 6; y: memCanvas.y + memCanvas.height * 0.5 - 5
                text: "50%"; color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            // ──── Disk I/O ────
            Text {
                id: ioLabel
                anchors.top: memCanvas.bottom; anchors.topMargin: root.graphSpacing
                anchors.left: parent.left; anchors.leftMargin: 6
                text: "Disk"; color: "#b39ddb"
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            Canvas {
                id: ioCanvas
                anchors.top: ioLabel.bottom
                anchors.left: parent.left; anchors.leftMargin: root.graphLeftMargin
                anchors.right: parent.right; anchors.rightMargin: root.graphRightMargin
                height: root.graphHeight

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (root.statsData.length < 2) return;
                    drawNetGrid(ctx, width, height);
                    root.drawStepAreaScaled(ctx, width, height, root.ioMax, function(p) { return p.io.r; }, Qt.rgba(0.70, 0.62, 0.86, 0.6));
                    root.drawStepAreaScaled(ctx, width, height, root.ioMax, function(p) { return p.io.w; }, Qt.rgba(0.94, 0.33, 0.31, 0.5));
                    root.drawHoverLine(ctx, width, height);
                    root.drawTooltip(ctx, width, height, "io");
                }

                function drawNetGrid(ctx, w, h) {
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.07);
                    ctx.lineWidth = 1;
                    for (var g = 0.25; g <= 0.75; g += 0.25) {
                        var gy = h - g * h;
                        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke();
                    }
                }

                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: function(mouse) { root.onHover("io", mouse.x, parent.width); }
                    onExited: root.onHoverExit()
                }
            }

            Text {
                x: 6; y: ioCanvas.y + ioCanvas.height * 0.5 - 5
                text: root.formatRate(root.ioMax * 0.5); color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            // ──── Network ────
            Text {
                id: netLabel
                anchors.top: ioCanvas.bottom; anchors.topMargin: root.graphSpacing
                anchors.left: parent.left; anchors.leftMargin: 6
                text: "Net"; color: "#42a5f5"
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            Canvas {
                id: netCanvas
                anchors.top: netLabel.bottom
                anchors.left: parent.left; anchors.leftMargin: root.graphLeftMargin
                anchors.right: parent.right; anchors.rightMargin: root.graphRightMargin
                height: root.graphHeight

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (root.statsData.length < 2) return;
                    drawNetGrid(ctx, width, height);
                    root.drawStepAreaScaled(ctx, width, height, root.netMax, function(p) { return p.net.r; }, Qt.rgba(0.26, 0.65, 0.96, 0.6));
                    root.drawStepAreaScaled(ctx, width, height, root.netMax, function(p) { return p.net.t; }, Qt.rgba(0.94, 0.33, 0.31, 0.5));
                    root.drawHoverLine(ctx, width, height);
                    root.drawTooltip(ctx, width, height, "net");
                }

                function drawNetGrid(ctx, w, h) {
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.07);
                    ctx.lineWidth = 1;
                    for (var g = 0.25; g <= 0.75; g += 0.25) {
                        var gy = h - g * h;
                        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke();
                    }
                }

                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: function(mouse) { root.onHover("net", mouse.x, parent.width); }
                    onExited: root.onHoverExit()
                }
            }

            Text {
                x: 6; y: netCanvas.y + netCanvas.height * 0.5 - 5
                text: root.formatRate(root.netMax * 0.5); color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            // ──── Load + PSI ────
            Text {
                id: loadLabel
                anchors.top: netCanvas.bottom; anchors.topMargin: root.graphSpacing
                anchors.left: parent.left; anchors.leftMargin: 6
                text: "Load"; color: "#ffb74d"
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            Canvas {
                id: loadCanvas
                anchors.top: loadLabel.bottom
                anchors.left: parent.left; anchors.leftMargin: root.graphLeftMargin
                anchors.right: parent.right; anchors.rightMargin: root.graphRightMargin
                height: root.graphHeight

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    if (root.statsData.length < 2) return;

                    var w = width, h = height;

                    // Grid
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.07);
                    ctx.lineWidth = 1;
                    for (var g = 0.25; g <= 0.75; g += 0.25) {
                        var gy = h - g * h;
                        ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke();
                    }

                    // PSI areas (scaled to psiMax)
                    root.drawStepAreaScaled(ctx, w, h, root.psiMax, function(p) { return p.psi.i; }, Qt.rgba(0.94, 0.33, 0.31, 0.4));
                    root.drawStepAreaScaled(ctx, w, h, root.psiMax, function(p) { return p.psi.c; }, Qt.rgba(1.0, 0.72, 0.30, 0.4));
                    root.drawStepAreaScaled(ctx, w, h, root.psiMax, function(p) { return p.psi.m; }, Qt.rgba(0.50, 0.78, 0.51, 0.4));

                    // Load average lines (scaled to loadMax)
                    drawLoadLine(ctx, w, h, function(p) { return p.load.l15; }, Qt.rgba(1, 0.72, 0.30, 0.25), 1);
                    drawLoadLine(ctx, w, h, function(p) { return p.load.l5; }, Qt.rgba(1, 0.72, 0.30, 0.45), 1);
                    // Load 1m as filled area
                    root.drawStepAreaScaled(ctx, w, h, root.loadMax, function(p) { return p.load.l1; }, Qt.rgba(1, 0.72, 0.30, 0.35));
                    drawLoadLine(ctx, w, h, function(p) { return p.load.l1; }, Qt.rgba(1, 0.72, 0.30, 0.9), 1.5);

                    root.drawHoverLine(ctx, w, h);
                    root.drawTooltip(ctx, w, h, "load");
                }

                function drawLoadLine(ctx, w, h, getData, color, lw) {
                    var d = root.statsData;
                    var segments = root.buildSegments(d);
                    ctx.strokeStyle = color;
                    ctx.lineWidth = lw;
                    for (var s = 0; s < segments.length; s++) {
                        var seg = segments[s];
                        if (seg.start === seg.end) continue;
                        ctx.beginPath();
                        for (var j = seg.start; j <= seg.end; j++) {
                            var x = root.xForTime(d[j].t, w);
                            var y = h - (Math.min(getData(d[j]), root.loadMax) / root.loadMax) * h;
                            if (j === seg.start) ctx.moveTo(x, y);
                            else {
                                ctx.lineTo(x, y);
                                if (j < seg.end) ctx.lineTo(root.xForTime(d[j + 1].t, w), y);
                            }
                        }
                        ctx.stroke();
                    }
                }

                MouseArea {
                    anchors.fill: parent; hoverEnabled: true
                    onPositionChanged: function(mouse) { root.onHover("load", mouse.x, parent.width); }
                    onExited: root.onHoverExit()
                }
            }

            Text {
                x: 6; y: loadCanvas.y + loadCanvas.height * 0.5 - 5
                text: (root.loadMax * 0.5).toFixed(1); color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.fontSizeTiny
            }

            // X-axis time labels (shared)
            Repeater {
                model: root.timeLabels
                Text {
                    required property var modelData
                    x: cpuCanvas.x + modelData.x - implicitWidth / 2
                    y: loadCanvas.y + loadCanvas.height + 3
                    text: modelData.label; color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                }
            }
        }
    }

    property var timeLabels: {
        if (statsData.length < 2) return [];
        var w = cpuCanvas.width;
        if (w <= 0) return [];
        var tr = timeRange();
        var labels = [];
        var count = 6;
        var dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
        for (var i = 0; i <= count; i++) {
            var t = tr.min + (tr.range * i / count);
            var date = new Date(t * 1000);
            var hh = date.getHours();
            var mm = date.getMinutes();
            labels.push({x: (i / count) * w, label: dayNames[date.getDay()] + " " + (hh < 10 ? "0" : "") + hh + ":" + (mm < 10 ? "0" : "") + mm});
        }
        return labels;
    }
}
