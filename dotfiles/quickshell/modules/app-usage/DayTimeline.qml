import QtQuick
import "../../components" as Components
import "../../config" as AppConfig

// Day-mode activity timeline: canvas track of category blocks with the focus
// overlay, hour ticks and "now" marker, plus hover inspection with a tooltip.
// The canvas only repaints on demand — the popup calls repaint() after data
// lands (property changes alone don't trigger a paint).
Column {
    id: root

    property var timeline: null
    property var segments: []
    property var focusBlocks: []
    property bool isLive: false

    property int hoverIdx: -1
    property real hoverX: 0

    spacing: 2

    function repaint() {
        timelineCanvas.requestPaint();
    }

    // HH:MM from seconds-since-midnight (timeline segment coords).
    function hms(sec) {
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return p(h) + ":" + p(m);
    }

    Canvas {
        id: timelineCanvas
        width: parent.width
        height: 44

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            if (!root.timeline) return;

            var tlStart = root.timeline.start || 0;
            var span = root.timeline.span || 1;
            var blocks = root.timeline.blocks || [];
            var w = width;
            var trackY = 2;
            var trackH = 22;

            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.04);
            roundRect(ctx, 0, trackY, w, trackH, 5);
            ctx.fill();

            for (var i = 0; i < blocks.length; i++) {
                var b = blocks[i];
                var x1 = ((b.s - tlStart) / span) * w;
                var x2 = ((b.e - tlStart) / span) * w;
                var bw = Math.max(1.5, x2 - x1);

                ctx.fillStyle = b.col;
                ctx.globalAlpha = 0.85;
                roundRect(ctx, x1, trackY + 1, bw, trackH - 2, 2);
                ctx.fill();

                ctx.globalAlpha = 0.2;
                ctx.fillStyle = "#ffffff";
                roundRect(ctx, x1, trackY + 1, bw, 1, 0);
                ctx.fill();
            }
            ctx.globalAlpha = 1.0;

            // Focus sessions overlay — a highlight band over
            // the activity track plus a solid accent top edge.
            // Only on the live day: focusBlocks are today-only,
            // so they'd land at wrong times on a historical day.
            var fb = root.isLive ? (root.focusBlocks || []) : [];
            for (var fi = 0; fi < fb.length; fi++) {
                var f = fb[fi];
                var fx1 = ((f.s - tlStart) / span) * w;
                var fbw = Math.max(2, (((f.e - tlStart) / span) * w) - fx1);
                var done = (f.status === "completed" || f.status === "active");

                ctx.fillStyle = "#0caf49";
                ctx.globalAlpha = done ? 0.16 : 0.07;
                roundRect(ctx, fx1, trackY, fbw, trackH, 2);
                ctx.fill();

                ctx.globalAlpha = done ? 0.95 : 0.45;
                roundRect(ctx, fx1, trackY, fbw, 2, 1);
                ctx.fill();
            }
            ctx.globalAlpha = 1.0;

            // "Now" marker — only on the live current day;
            // a past day's right edge is just end-of-day.
            if (root.isLive) {
                var nx = w - 1.5;
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.1);
                ctx.fillRect(nx - 3, trackY - 1, 7, trackH + 2);
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.9);
                ctx.fillRect(nx, trackY - 1, 2, trackH + 2);
                ctx.beginPath();
                ctx.moveTo(nx - 3, trackY - 1);
                ctx.lineTo(nx + 4, trackY - 1);
                ctx.lineTo(nx + 0.5, trackY + 4);
                ctx.closePath();
                ctx.fill();
            }

            ctx.font = "12px '" + AppConfig.Config.theme.fontFamily + "'";
            ctx.textAlign = "center";

            var firstHour = Math.ceil(tlStart / 3600);
            var endSec = tlStart + span;
            // Choose an hour stride so labels keep ~44px apart and never overlap.
            var pxPerHour = (3600 / span) * w;
            var minGap = 44;
            var steps = [1, 2, 3, 4, 6, 8, 12, 24];
            var step = steps[steps.length - 1];
            for (var si = 0; si < steps.length; si++) {
                if (steps[si] * pxPerHour >= minGap) { step = steps[si]; break; }
            }
            for (var h = firstHour; h * 3600 < endSec; h++) {
                var hx = ((h * 3600 - tlStart) / span) * w;
                if (hx < 24 || hx > w - 24) continue;
                var labeled = (h % step === 0);
                ctx.fillStyle = Qt.rgba(1, 1, 1, labeled ? 0.12 : 0.05);
                ctx.fillRect(hx, trackY, 1, trackH);
                if (labeled) {
                    ctx.fillStyle = Qt.rgba(1, 1, 1, 0.4);
                    ctx.fillText(h + ":00", hx, trackY + trackH + 14);
                }
            }
        }

        function roundRect(ctx, x, y, w, h, r) {
            ctx.beginPath();
            ctx.moveTo(x + r, y);
            ctx.lineTo(x + w - r, y);
            ctx.quadraticCurveTo(x + w, y, x + w, y + r);
            ctx.lineTo(x + w, y + h - r);
            ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
            ctx.lineTo(x + r, y + h);
            ctx.quadraticCurveTo(x, y + h, x, y + h - r);
            ctx.lineTo(x, y + r);
            ctx.quadraticCurveTo(x, y, x + r, y);
            ctx.closePath();
        }

        // Hover: find the segment under the cursor.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: function (mouse) {
                root.hoverX = mouse.x;
                var tl = root.timeline;
                if (!tl) { root.hoverIdx = -1; return; }
                var t = (tl.start || 0) + (mouse.x / width) * (tl.span || 1);
                var segs = root.segments;
                var found = -1;
                for (var i = 0; i < segs.length; i++) {
                    if (t >= segs[i].s && t <= segs[i].e) { found = i; break; }
                }
                root.hoverIdx = found;
            }
            onExited: root.hoverIdx = -1
        }

        // Hover indicator line.
        Rectangle {
            visible: root.hoverIdx >= 0
            width: 1.5
            height: 24
            y: 1
            x: root.hoverX - 0.75
            color: Qt.rgba(1, 1, 1, 0.65)
        }

        // Tooltip showing category · subcategory + app + time range.
        Rectangle {
            id: tlTip
            readonly property var seg: (root.hoverIdx >= 0 && root.hoverIdx < root.segments.length) ? root.segments[root.hoverIdx] : null
            visible: seg !== null
            z: 100
            width: tipCol.implicitWidth + 16
            height: tipCol.implicitHeight + 10
            radius: 6
            color: Qt.rgba(0.05, 0.05, 0.07, 0.97)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
            x: Math.max(0, Math.min(root.hoverX - width / 2, parent.width - width))
            y: -(height + 6)

            Column {
                id: tipCol
                anchors.centerIn: parent
                spacing: 2

                Row {
                    spacing: 6
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: tlTip.seg ? tlTip.seg.col : "transparent"
                    }
                    Components.ThemedText {
                        text: tlTip.seg ? (tlTip.seg.cat + "  ·  " + tlTip.seg.sub) : ""
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        font.bold: true
                    }
                }
                Components.ThemedText {
                    text: tlTip.seg ? (tlTip.seg.cls + "   " + root.hms(tlTip.seg.s) + "–" + root.hms(tlTip.seg.e)) : ""
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                }
            }
        }
    }
}
