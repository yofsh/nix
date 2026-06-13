import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Graph section: day header strip on top, then the hourly forecast canvas —
// temperature curve, precipitation bars, wind band, HA sensor + rain-event
// overlays, "now" marker and hover tooltip — plus y-axis labels and legend.
// `popup` is the weather Popup root; it calls requestPaint() after each
// data update.
Item {
    id: root

    property var popup: null

    // Hover state
    property real hoverX: -1
    property int hoverIdx: -1

    function requestPaint() {
        graphCanvas.requestPaint();
    }

    // Y-axis label positions
    property var yLabels: {
        if (popup.hourlyTemp.length < 2) return [];
        var h = graphCanvas.height;
        if (h <= 0) return [];
        var tMin = popup.hourlyTemp[0], tMax = popup.hourlyTemp[0];
        for (var i = 0; i < popup.hourlyTemp.length; i++) {
            if (popup.hourlyTemp[i] < tMin) tMin = popup.hourlyTemp[i];
            if (popup.hourlyTemp[i] > tMax) tMax = popup.hourlyTemp[i];
        }
        tMin = Math.floor(tMin / 5) * 5 - 2;
        tMax = Math.ceil(tMax / 5) * 5 + 2;
        var tRange = tMax - tMin || 1;
        var step = tRange <= 15 ? 5 : 10;
        var labels = [];
        for (var t = Math.ceil(tMin / step) * step; t <= tMax; t += step) {
            labels.push({ y: h - ((t - tMin) / tRange) * h, label: t + "°" });
        }
        return labels;
    }

    // Day header row with icons
    DailyForecast {
        id: dayHeaderRow
        anchors.top: parent.top
        anchors.left: graphCanvas.left
        anchors.right: graphCanvas.right
        height: 66
        popup: root.popup
    }

    // Y-axis labels (temperature)
    Repeater {
        model: root.yLabels
        Components.ThemedText {
            x: 4
            y: graphCanvas.y + modelData.y - 5
            text: modelData.label
            muted: true
            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
        }
    }

    // Legend
    Row {
        visible: popup.haLoaded || popup.haRainLoaded
        anchors.right: graphCanvas.right
        anchors.top: dayHeaderRow.bottom
        anchors.topMargin: 2
        z: 1
        spacing: 10

        Repeater {
            model: popup.haSensors
            Row {
                spacing: 3
                Rectangle { width: 12; height: 2; color: modelData.color; anchors.verticalCenter: parent.verticalCenter; border.width: 0; radius: 1 }
                Components.ThemedText {
                    text: modelData.label
                    color: Qt.rgba(1, 1, 1, 0.4)
                    font.pixelSize: 8
                }
            }
        }
        Row {
            visible: popup.haRainLoaded
            spacing: 3
            Rectangle { width: 8; height: 8; color: Qt.rgba(0.3, 0.8, 0.3, 0.5); anchors.verticalCenter: parent.verticalCenter; border.width: 0; radius: 1 }
            Components.ThemedText {
                text: "Rain (sensor)"
                color: Qt.rgba(1, 1, 1, 0.4)
                font.pixelSize: 8
            }
        }
    }

    // Canvas graph
    Canvas {
        id: graphCanvas
        anchors.top: dayHeaderRow.bottom
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 12
        height: parent.height - dayHeaderRow.height - 12

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            var temps = popup.hourlyTemp;
            var precips = popup.hourlyPrecip;
            var winds = popup.hourlyWind;
            if (temps.length < 2) return;

            var w = width;
            var h = height;
            var n = temps.length;

            // Temperature range with padding
            var tMin = temps[0], tMax = temps[0];
            for (var i = 0; i < n; i++) {
                if (temps[i] < tMin) tMin = temps[i];
                if (temps[i] > tMax) tMax = temps[i];
            }
            tMin = Math.floor(tMin / 5) * 5 - 2;
            tMax = Math.ceil(tMax / 5) * 5 + 2;
            var tRange = tMax - tMin || 1;

            // Precip max
            var pMax = 0.5;
            for (var ip = 0; ip < precips.length; ip++) {
                if (precips[ip] > pMax) pMax = precips[ip];
            }

            // Wind max
            var wMax = 10;
            for (var iw = 0; iw < winds.length; iw++) {
                if (winds[iw] > wMax) wMax = winds[iw];
            }

            // ── Grid lines ──
            var gridStep = tRange <= 15 ? 5 : 10;
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.06);
            ctx.lineWidth = 1;
            for (var gt = Math.ceil(tMin / gridStep) * gridStep; gt <= tMax; gt += gridStep) {
                var gy = h - ((gt - tMin) / tRange) * h;
                ctx.beginPath();
                ctx.moveTo(0, gy);
                ctx.lineTo(w, gy);
                ctx.stroke();
            }

            // ── Day boundary lines ──
            var times = popup.hourlyTime;
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12);
            ctx.lineWidth = 1;
            for (var id = 1; id < times.length; id++) {
                if (times[id].indexOf("T00:00") !== -1) {
                    var dx = (id / n) * w;
                    ctx.beginPath();
                    ctx.moveTo(dx, 0);
                    ctx.lineTo(dx, h);
                    ctx.stroke();
                }
            }

            // ── Precipitation bars ──
            var barW = Math.max(2, w / n - 1);
            var precipH = h * 0.3;  // bottom 30% for precip
            for (var ip2 = 0; ip2 < precips.length; ip2++) {
                if (precips[ip2] <= 0) continue;
                var px = (ip2 / n) * w;
                var pH = Math.min((precips[ip2] / pMax) * precipH, precipH);
                ctx.fillStyle = Qt.rgba(0.39, 0.71, 0.96, 0.5);
                ctx.fillRect(px, h - pH, barW, pH);
            }

            // ── HA rain sensor events (drawn over precip bars) ──
            if (popup.haRainLoaded) {
                var forecastStartR = new Date(times[0]).getTime();
                var forecastEndR = new Date(times[n - 1]).getTime();
                var forecastSpanR = forecastEndR - forecastStartR || 1;

                ctx.fillStyle = Qt.rgba(0.3, 0.8, 0.3, 0.7);
                for (var ir = 0; ir < popup.haRainEvents.length; ir++) {
                    var evt = popup.haRainEvents[ir];
                    var rs = Math.max(evt.start, forecastStartR);
                    var re = Math.min(evt.end, forecastEndR);
                    if (rs >= re) continue;
                    var rx = ((rs - forecastStartR) / forecastSpanR) * w;
                    var rw = ((re - forecastStartR) / forecastSpanR) * w - rx;
                    ctx.fillRect(rx, h - h * 0.15, Math.max(rw, 2), h * 0.15);
                }
            }

            // ── Wind area (subtle) ──
            ctx.beginPath();
            ctx.moveTo(0, h);
            for (var iw2 = 0; iw2 < winds.length; iw2++) {
                var wx = (iw2 / n) * w;
                var wh = (winds[iw2] / wMax) * h * 0.2;  // bottom 20%
                ctx.lineTo(wx, h - wh);
            }
            ctx.lineTo(w, h);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.04);
            ctx.fill();

            // ── Temperature curve — filled gradient ──
            // Fill below
            ctx.beginPath();
            ctx.moveTo(0, h);
            for (var it = 0; it < n; it++) {
                var tx = (it / n) * w;
                var ty = h - ((temps[it] - tMin) / tRange) * h;
                if (it === 0) ctx.lineTo(tx, ty);
                else ctx.lineTo(tx, ty);
            }
            ctx.lineTo(w, h);
            ctx.closePath();

            var grad = ctx.createLinearGradient(0, 0, 0, h);
            grad.addColorStop(0, Qt.rgba(1, 0.6, 0, 0.25));
            grad.addColorStop(0.5, Qt.rgba(1, 0.8, 0.2, 0.08));
            grad.addColorStop(1, Qt.rgba(0.4, 0.7, 1, 0.05));
            ctx.fillStyle = grad;
            ctx.fill();

            // Temperature line
            ctx.beginPath();
            for (var it2 = 0; it2 < n; it2++) {
                var tx2 = (it2 / n) * w;
                var ty2 = h - ((temps[it2] - tMin) / tRange) * h;
                if (it2 === 0) ctx.moveTo(tx2, ty2);
                else ctx.lineTo(tx2, ty2);
            }
            var tempGrad = ctx.createLinearGradient(0, 0, w, 0);
            for (var ig = 0; ig < n; ig += Math.max(1, Math.floor(n / 20))) {
                var frac = ig / n;
                var c = popup.tempColor(temps[ig]);
                tempGrad.addColorStop(frac, c);
            }
            ctx.strokeStyle = tempGrad;
            ctx.lineWidth = 2;
            ctx.stroke();

            // ── HA sensor overlays ──
            if (popup.haLoaded && popup.haSensors.length > 0 && times.length > 0) {
                var forecastStart = new Date(times[0]).getTime();
                var forecastEnd = new Date(times[n - 1]).getTime();
                var forecastSpan = forecastEnd - forecastStart || 1;

                for (var si = 0; si < popup.haSensors.length; si++) {
                    var sensor = popup.haSensors[si];
                    ctx.beginPath();
                    var haStarted = false;
                    for (var ih = 0; ih < sensor.times.length; ih++) {
                        var haTs = sensor.times[ih];
                        if (haTs < forecastStart || haTs > forecastEnd) continue;
                        var hax = ((haTs - forecastStart) / forecastSpan) * w;
                        var hay = h - ((sensor.temps[ih] - tMin) / tRange) * h;
                        if (!haStarted) { ctx.moveTo(hax, hay); haStarted = true; }
                        else ctx.lineTo(hax, hay);
                    }
                    if (haStarted) {
                        ctx.strokeStyle = sensor.color;
                        ctx.lineWidth = 1.5;
                        ctx.stroke();
                    }
                }
            }

            // ── "Now" marker ──
            // hourlyTime is local ISO (timezone=auto) — compare with a local key, not UTC
            var nowIso = popup.localHourStr(new Date());
            var nowIdx = -1;
            for (var in2 = 0; in2 < times.length; in2++) {
                if (times[in2].substring(0, 13) === nowIso) { nowIdx = in2; break; }
            }
            if (nowIdx >= 0) {
                var nx = (nowIdx / n) * w;
                var ny = h - ((temps[nowIdx] - tMin) / tRange) * h;
                // Dashed line
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.3);
                ctx.lineWidth = 1;
                ctx.setLineDash([3, 3]);
                ctx.beginPath();
                ctx.moveTo(nx, 0);
                ctx.lineTo(nx, h);
                ctx.stroke();
                ctx.setLineDash([]);
                // Dot
                ctx.beginPath();
                ctx.arc(nx, ny, 4, 0, 2 * Math.PI);
                ctx.fillStyle = "white";
                ctx.fill();
                ctx.beginPath();
                ctx.arc(nx, ny, 2, 0, 2 * Math.PI);
                ctx.fillStyle = popup.tempColor(temps[nowIdx]);
                ctx.fill();
            }

            // ── Hover tooltip ──
            if (root.hoverIdx >= 0 && root.hoverIdx < n) {
                var hi = root.hoverIdx;
                var hx = (hi / n) * w;
                var hy = h - ((temps[hi] - tMin) / tRange) * h;

                // Crosshair
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.25);
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

                // Tooltip
                var time = times[hi] || "";
                var hDate = new Date(time);
                var hDays = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                var hHH = hDate.getHours();
                var hDay = hDays[hDate.getDay()];
                var timeStr = hDay + " " + (hHH < 10 ? "0" : "") + hHH + ":00";
                var label = Math.round(temps[hi]) + "°  " + popup.weatherDesc(popup.hourlyCode[hi]);
                var line2 = "󰖗 " + precips[hi].toFixed(1) + "mm  󰖝 " + Math.round(winds[hi]) + "km/h";
                var line3 = timeStr;

                // Find matching HA sensor values
                var haLines = [];
                var haColors = [];
                if (popup.haLoaded && times[hi]) {
                    var hoverEpoch = new Date(times[hi]).getTime();
                    for (var isi = 0; isi < popup.haSensors.length; isi++) {
                        var sen = popup.haSensors[isi];
                        for (var iha = 0; iha < sen.times.length; iha++) {
                            if (Math.abs(sen.times[iha] - hoverEpoch) < 1800000) {
                                haLines.push(sen.label + ": " + sen.temps[iha].toFixed(1) + "°");
                                haColors.push(sen.color);
                                break;
                            }
                        }
                    }
                }

                var lines = [label, line2, line3];
                for (var ihl = 0; ihl < haLines.length; ihl++) lines.push(haLines[ihl]);

                ctx.font = "10px '" + AppConfig.Config.theme.fontFamily + "'";
                var tw = 0;
                for (var il = 0; il < lines.length; il++) {
                    var lw = ctx.measureText(lines[il]).width;
                    if (lw > tw) tw = lw;
                }
                var tooltipX = hx + 10;
                if (tooltipX + tw + 12 > w) tooltipX = hx - tw - 20;
                var boxH = 12 * lines.length + 6;
                var tooltipY = Math.max(10, Math.min(hy - 24, h - boxH - 6));

                // Background
                ctx.fillStyle = Qt.rgba(0, 0, 0, 0.8);
                var boxW = tw + 12;
                var boxR = 4;
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

                // Text
                ctx.textAlign = "left";
                ctx.font = "bold 10px '" + AppConfig.Config.theme.fontFamily + "'";
                ctx.fillStyle = "white";
                ctx.fillText(label, tooltipX + 6, tooltipY + 13);
                ctx.font = "10px '" + AppConfig.Config.theme.fontFamily + "'";
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.6);
                ctx.fillText(line2, tooltipX + 6, tooltipY + 25);
                ctx.fillStyle = Qt.rgba(1, 1, 1, 0.4);
                ctx.fillText(line3, tooltipX + 6, tooltipY + 37);
                for (var iht = 0; iht < haLines.length; iht++) {
                    ctx.fillStyle = haColors[iht];
                    ctx.fillText(haLines[iht], tooltipX + 6, tooltipY + 49 + iht * 12);
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: function(mouse) {
                var n = popup.hourlyTemp.length;
                if (n === 0) return;
                var idx = Math.round((mouse.x / parent.width) * n);
                idx = Math.max(0, Math.min(n - 1, idx));
                root.hoverIdx = idx;
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
}
