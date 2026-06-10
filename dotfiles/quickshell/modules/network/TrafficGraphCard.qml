import QtQuick
import "../../components" as Components
import "../../config" as AppConfig
import "../../helpers/Format.js" as Format

// Traffic bar graph card: combined up/down rate history with auto-scaled axis.
// The popup root pushes new samples into trafficHistory and calls repaint().
Rectangle {
    id: root

    property var trafficHistory: []
    property int trafficMaxHistory: 300

    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    function repaint() {
        trafficGraph.requestPaint();
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4

        Row {
            width: parent.width
            spacing: 6
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF04E1)
                color: "#90caf9"
                font.pixelSize: 14
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Traffic"
                font.bold: true
            }
            Item { width: 1; height: 1 }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: -2
                Components.ThemedText {
                    text: {
                        var h = root.trafficHistory;
                        if (h.length === 0) return "↑ —";
                        return "↑ " + Format.rate(h[h.length - 1].tx);
                    }
                    color: "#ff9800"
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                Components.ThemedText {
                    text: {
                        var h = root.trafficHistory;
                        if (h.length === 0) return "↓ —";
                        return "↓ " + Format.rate(h[h.length - 1].rx);
                    }
                    color: "#42a5f5"
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
            }
            Item { width: 8; height: 1 }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: -2
                Components.ThemedText {
                    text: {
                        var h = root.trafficHistory;
                        if (h.length === 0) return "max ↑ —";
                        var m = 0;
                        for (var i = 0; i < h.length; i++)
                            if (h[i].tx > m) m = h[i].tx;
                        return "max ↑ " + Format.rate(m);
                    }
                    color: Qt.rgba(1, 0.6, 0, 0.6)
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                Components.ThemedText {
                    text: {
                        var h = root.trafficHistory;
                        if (h.length === 0) return "max ↓ —";
                        var m = 0;
                        for (var i = 0; i < h.length; i++)
                            if (h[i].rx > m) m = h[i].rx;
                        return "max ↓ " + Format.rate(m);
                    }
                    color: Qt.rgba(0.26, 0.65, 0.96, 0.6)
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
            }
        }

        Canvas {
            id: trafficGraph
            width: parent.width
            height: parent.height - 24

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var h = root.trafficHistory;
                if (h.length === 0) return;

                var rawMax = 0;
                for (var i = 0; i < h.length; i++) {
                    if (h[i].tx > rawMax) rawMax = h[i].tx;
                    if (h[i].rx > rawMax) rawMax = h[i].rx;
                }
                // Nice auto-scale ceiling with headroom
                var maxVal;
                if (rawMax <= 0) maxVal = 1024;
                else if (rawMax < 1024) maxVal = 1024;
                else if (rawMax < 10240) maxVal = Math.ceil(rawMax / 1024) * 1024;
                else if (rawMax < 102400) maxVal = Math.ceil(rawMax / 10240) * 10240;
                else if (rawMax < 1048576) maxVal = Math.ceil(rawMax / 102400) * 102400;
                else maxVal = Math.ceil(rawMax / 1048576) * 1048576;
                if (maxVal < rawMax * 1.1) maxVal = Math.ceil(rawMax * 1.15);

                var halfH = height / 2;
                var barW = width / root.trafficMaxHistory;
                var offset = width - h.length * barW;

                // Grid: center + quarter lines
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.06);
                ctx.lineWidth = 1;
                for (var g = 0.25; g <= 0.75; g += 0.25) {
                    ctx.beginPath();
                    ctx.moveTo(0, halfH - g * halfH);
                    ctx.lineTo(width, halfH - g * halfH);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.moveTo(0, halfH + g * halfH);
                    ctx.lineTo(width, halfH + g * halfH);
                    ctx.stroke();
                }
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.10);
                ctx.beginPath();
                ctx.moveTo(0, halfH);
                ctx.lineTo(width, halfH);
                ctx.stroke();

                for (var i = 0; i < h.length; i++) {
                    var x = offset + i * barW;
                    var txR = Math.min(1, h[i].tx / maxVal);
                    var rxR = Math.min(1, h[i].rx / maxVal);

                    if (txR > 0) {
                        var txH = txR * halfH;
                        var ta = 0.3 + 0.7 * txR;
                        ctx.fillStyle = "rgba(255, 152, 0, " + ta + ")";
                        ctx.fillRect(x, halfH - txH, Math.max(1, barW - 0.3), txH);
                    }
                    if (rxR > 0) {
                        var rxH = rxR * halfH;
                        var ra = 0.3 + 0.7 * rxR;
                        ctx.fillStyle = "rgba(66, 165, 245, " + ra + ")";
                        ctx.fillRect(x, halfH, Math.max(1, barW - 0.3), rxH);
                    }
                }

                ctx.fillStyle = "rgba(255,255,255,0.35)";
                ctx.font = "10px '" + AppConfig.Config.theme.fontFamily + "'";
                ctx.textAlign = "left";
                ctx.fillText("↑ " + Format.rate(maxVal), 2, 10);
                ctx.fillText(Format.rate(maxVal / 2), 2, halfH * 0.5 + 3);
                ctx.fillText(Format.rate(maxVal / 2), 2, halfH * 1.5 + 3);
                ctx.fillText("↓ " + Format.rate(maxVal), 2, height - 3);
            }
        }
    }
}
