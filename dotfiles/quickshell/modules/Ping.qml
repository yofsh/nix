import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: graphCanvas.width + pingColumn.width + 4
    implicitHeight: parent ? parent.height : 30

    property string target: "1.1.1.1"
    property int currentPing: -1  // -1 = no data yet, -2 = timeout
    property int maxPing: 0       // highest ping currently on graph
    property int maxHistory: 60
    property var history: []

    function parsePingLine(line) {
        // Match: time=12.3 ms
        var match = line.match(/time=([\d.]+)\s*ms/);
        if (match) {
            root.currentPing = Math.round(parseFloat(match[1]));
        } else if (line.indexOf("no answer") >= 0 || line.indexOf("Request timeout") >= 0) {
            root.currentPing = -2;
        } else {
            return; // ignore non-reply lines (header, stats, etc.)
        }
        var h = root.history.slice();
        h.push(root.currentPing);
        if (h.length > root.maxHistory)
            h.shift();
        root.history = h;

        var mx = 0;
        for (var i = 0; i < h.length; i++)
            if (h[i] > mx) mx = h[i];
        root.maxPing = mx;

        graphCanvas.requestPaint();
    }

    property color pingColor: {
        if (currentPing < 0) return Helpers.Colors.disconnected;
        if (currentPing <= 30) return "#4caf50";
        if (currentPing <= 70) return "#ff9800";
        return "#f44336";
    }

    Canvas {
        id: graphCanvas
        width: root.maxHistory
        height: root.implicitHeight
        anchors.verticalCenter: parent.verticalCenter

        function pingColor(val) {
            if (val <= 30) return "#4caf50";
            if (val <= 70) return "#ff9800";
            return "#f44336";
        }

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var h = root.history;
            if (h.length === 0) return;
            var offset = width - h.length;

            // Draw filled area segments grouped by color
            var i = 0;
            while (i < h.length) {
                var val = h[i];
                if (val === -1) { i++; continue; }

                if (val === -2) {
                    // Timeout: collect consecutive timeouts into one filled rect
                    var start = i;
                    while (i < h.length && h[i] === -2) i++;
                    ctx.fillStyle = "#f44336";
                    ctx.fillRect(offset + start, 0, i - start, height);
                    continue;
                }

                // Normal ping: collect consecutive same-color samples into a filled path
                var color = pingColor(val);
                var start2 = i;
                while (i < h.length && h[i] >= 0 && pingColor(h[i]) === color) i++;

                ctx.beginPath();
                ctx.moveTo(offset + start2, height);
                for (var j = start2; j < i; j++) {
                    var clamped = Math.min(h[j], 100);
                    var barH = (clamped / 100) * height;
                    ctx.lineTo(offset + j, height - barH);
                    ctx.lineTo(offset + j + 1, height - barH);
                }
                ctx.lineTo(offset + i, height);
                ctx.closePath();
                ctx.fillStyle = color;
                ctx.fill();
            }
        }
    }

    Column {
        id: pingColumn
        anchors.left: graphCanvas.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2
        width: Math.max(pingLabel.implicitWidth, pingValue.implicitWidth)

        Text {
            id: pingLabel
            text: root.maxPing > 0 ? root.maxPing : "..."
            color: Helpers.Colors.textMuted
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 10
        }

        Text {
            id: pingValue
            text: root.currentPing === -1 ? "..." : (root.currentPing === -2 ? "×" : root.currentPing)
            color: root.pingColor
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 10
        }
    }

    Process {
        id: pingProc
        command: ["ping", "-Q", "0xB8", "-i", "1", root.target]
        running: root.target !== ""
        onRunningChanged: if (!running && root.target !== "") running = true
        stdout: SplitParser {
            onRead: data => root.parsePingLine(data)
        }
    }
}
