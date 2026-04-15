import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// Line chart with x/y axes, gridlines, hover crosshair, and tooltip.
// Inputs: `points` = array of {x, y} in chart units.
Item {
    id: root

    property var points: []
    property string xUnit: "s"
    property string yUnit: ""
    property color traceColor: Helpers.Colors.multimeterActive
    property string emptyText: ""
    property string caption: ""
    // If true, x is seconds — tooltip formats ms/µs below 1 s.
    property bool xIsTime: true

    readonly property real plotLeft: 44
    readonly property real plotRight: 6
    readonly property real plotTop: 6
    readonly property real plotBottom: 18

    property real _xMin: 0
    property real _xMax: 1
    property real _yMin: 0
    property real _yMax: 1
    property int  _hoverIdx: -1

    function _recompute() {
        if (!points || points.length === 0) {
            _xMin = 0; _xMax = 1; _yMin = 0; _yMax = 1;
            return;
        }
        let xmin = points[0].x, xmax = points[0].x;
        let ymin = points[0].y, ymax = points[0].y;
        for (let i = 1; i < points.length; ++i) {
            const p = points[i];
            if (p.x < xmin) xmin = p.x;
            if (p.x > xmax) xmax = p.x;
            if (p.y < ymin) ymin = p.y;
            if (p.y > ymax) ymax = p.y;
        }
        const yspan = Math.max(1e-9, ymax - ymin);
        const ypad = yspan * 0.08;
        ymin -= ypad; ymax += ypad;
        if (xmin === xmax) xmax = xmin + 1;
        _xMin = xmin; _xMax = xmax; _yMin = ymin; _yMax = ymax;
    }
    onPointsChanged: { _recompute(); canvas.requestPaint(); }

    function _fmtY(v) {
        const abs = Math.abs(v);
        const u = yUnit;
        if (u === "V" || u === "A") {
            if (abs >= 1) return v.toFixed(3) + " " + u;
            if (abs >= 0.001) return (v * 1000).toFixed(2) + " m" + u;
            if (abs === 0) return "0 " + u;
            return (v * 1e6).toFixed(1) + " µ" + u;
        }
        if (abs >= 100) return v.toFixed(1) + (u ? " " + u : "");
        if (abs >= 10)  return v.toFixed(2) + (u ? " " + u : "");
        return v.toFixed(3) + (u ? " " + u : "");
    }
    function _fmtX(v) {
        if (!xIsTime) return v.toFixed(3) + " " + xUnit;
        const abs = Math.abs(v);
        if (abs === 0) return "0 s";
        if (abs >= 1)     return v.toFixed(2) + " s";
        if (abs >= 0.001) return (v * 1000).toFixed(1) + " ms";
        return (v * 1e6).toFixed(0) + " µs";
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1, 1, 1, 0.02)
        border.color: Qt.rgba(1, 1, 1, 0.06)
        radius: AppConfig.Config.theme.cardRadiusSmall
    }

    Canvas {
        id: canvas
        anchors.fill: parent

        function _px(p) {
            const plotW = width - root.plotLeft - root.plotRight;
            const plotH = height - root.plotTop - root.plotBottom;
            const x = root.plotLeft + ((p.x - root._xMin) / (root._xMax - root._xMin)) * plotW;
            const y = root.plotTop + plotH - ((p.y - root._yMin) / (root._yMax - root._yMin)) * plotH;
            return { x: x, y: y };
        }

        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);

            const plotW = width - root.plotLeft - root.plotRight;
            const plotH = height - root.plotTop - root.plotBottom;

            // Frame axes
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12);
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(root.plotLeft, root.plotTop);
            ctx.lineTo(root.plotLeft, root.plotTop + plotH);
            ctx.lineTo(root.plotLeft + plotW, root.plotTop + plotH);
            ctx.stroke();

            // Horizontal gridlines
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.05);
            ctx.setLineDash([2, 3]);
            for (let i = 1; i < 4; ++i) {
                const y = root.plotTop + (i / 4) * plotH;
                ctx.beginPath();
                ctx.moveTo(root.plotLeft, y);
                ctx.lineTo(root.plotLeft + plotW, y);
                ctx.stroke();
            }
            ctx.setLineDash([]);

            if (!root.points || root.points.length === 0) return;

            // Zero baseline if the range crosses zero
            if (root._yMin <= 0 && root._yMax >= 0) {
                const zeroY = root.plotTop + plotH
                    - ((0 - root._yMin) / (root._yMax - root._yMin)) * plotH;
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.14);
                ctx.lineWidth = 1;
                ctx.setLineDash([3, 3]);
                ctx.beginPath();
                ctx.moveTo(root.plotLeft, zeroY);
                ctx.lineTo(root.plotLeft + plotW, zeroY);
                ctx.stroke();
                ctx.setLineDash([]);
            }

            // Trace
            ctx.strokeStyle = root.traceColor;
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            for (let i = 0; i < root.points.length; ++i) {
                const p = _px(root.points[i]);
                if (i === 0) ctx.moveTo(p.x, p.y);
                else ctx.lineTo(p.x, p.y);
            }
            ctx.stroke();

            // Hover crosshair + dot
            if (root._hoverIdx >= 0 && root._hoverIdx < root.points.length) {
                const p = _px(root.points[root._hoverIdx]);
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.35);
                ctx.lineWidth = 1;
                ctx.beginPath();
                ctx.moveTo(p.x, root.plotTop);
                ctx.lineTo(p.x, root.plotTop + plotH);
                ctx.stroke();
                ctx.fillStyle = root.traceColor;
                ctx.beginPath();
                ctx.arc(p.x, p.y, 3, 0, 2 * Math.PI);
                ctx.fill();
            }
        }
    }

    // Y-axis labels (max, mid, min)
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.top: parent.top
        anchors.topMargin: root.plotTop - 3
        text: root._fmtY(root._yMax)
        color: Helpers.Colors.textMuted
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        text: root._fmtY((root._yMin + root._yMax) / 2)
        color: Helpers.Colors.textMuted
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
    }
    Text {
        anchors.left: parent.left
        anchors.leftMargin: 2
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.plotBottom - 3
        text: root._fmtY(root._yMin)
        color: Helpers.Colors.textMuted
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
    }

    // X-axis labels (min at left of plot, max at right)
    Text {
        x: root.plotLeft - implicitWidth / 2
        anchors.bottom: parent.bottom
        text: root._fmtX(root._xMin)
        color: Helpers.Colors.textMuted
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
    }
    Text {
        x: root.width - root.plotRight - implicitWidth
        anchors.bottom: parent.bottom
        text: root._fmtX(root._xMax)
        color: Helpers.Colors.textMuted
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
    }

    // Caption (top right)
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 4
        visible: root.caption !== ""
        text: root.caption
        color: Helpers.Colors.textMuted
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
    }

    // Empty state text
    Text {
        anchors.centerIn: parent
        visible: (!root.points || root.points.length === 0) && root.emptyText !== ""
        text: root.emptyText
        color: Helpers.Colors.textMuted
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        wrapMode: Text.WordWrap
        width: parent.width - 80
        horizontalAlignment: Text.AlignHCenter
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: {
            if (!root.points || root.points.length === 0) {
                root._hoverIdx = -1; canvas.requestPaint(); return;
            }
            const plotW = root.width - root.plotLeft - root.plotRight;
            const rel = mouseX - root.plotLeft;
            if (rel < 0 || rel > plotW
                || mouseY < root.plotTop
                || mouseY > root.height - root.plotBottom) {
                root._hoverIdx = -1; canvas.requestPaint(); return;
            }
            const xAt = root._xMin + (rel / plotW) * (root._xMax - root._xMin);
            let best = 0, bd = Math.abs(root.points[0].x - xAt);
            for (let i = 1; i < root.points.length; ++i) {
                const d = Math.abs(root.points[i].x - xAt);
                if (d < bd) { bd = d; best = i; }
            }
            root._hoverIdx = best;
            canvas.requestPaint();
        }
        onExited: { root._hoverIdx = -1; canvas.requestPaint(); }
    }

    Rectangle {
        id: tooltip
        visible: root._hoverIdx >= 0 && root.points && root.points.length > 0
        readonly property var hp: visible ? root.points[root._hoverIdx] : null
        color: Qt.rgba(0.10, 0.12, 0.18, 0.94)
        border.color: Qt.rgba(1, 1, 1, 0.18)
        radius: 3
        width: tooltipText.implicitWidth + 10
        height: tooltipText.implicitHeight + 6
        x: {
            if (!visible) return 0;
            const mx = hoverArea.mouseX;
            let nx = mx + 12;
            if (nx + width > root.width - 4) nx = mx - width - 10;
            return Math.max(2, nx);
        }
        y: {
            if (!visible) return 0;
            const my = hoverArea.mouseY;
            let ny = my - height - 6;
            if (ny < 2) ny = my + 14;
            return ny;
        }
        Text {
            id: tooltipText
            anchors.centerIn: parent
            text: tooltip.hp
                  ? root._fmtX(tooltip.hp.x) + "   " + root._fmtY(tooltip.hp.y)
                  : ""
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeTiny
        }
    }
}
