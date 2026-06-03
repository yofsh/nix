import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
Item {
    id: root

    property var context: null
    property var screen: null
    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false

    implicitWidth: 480
    implicitHeight: screen
        ? Math.min(mainCol.implicitHeight + 36, screen.height - barHeight - AppConfig.Config.theme.popupTopGap - 20)
        : mainCol.implicitHeight + 36

    property var usageData: null
    property var today: null
    property var week: null
    property string dateStr: ""
    property int hoverDay: -1   // index into week.days under the cursor, -1 = none

    // Per-project bar colors. Assigned by each project's rank in the week
    // master list so a project keeps the same color across the today list, the
    // 7-day list and the stacked chart.
    readonly property var palette: ["#89b4fa", "#a6e3a1", "#f38ba8", "#fab387", "#cba6f7", "#94e2d5", "#f9e2af", "#f2cdcd", "#74c7ec", "#eba0ac"]
    property var colorMap: ({})

    function rebuildColors() {
        var m = {};
        var ps = (week && week.projects) ? week.projects : [];
        for (var i = 0; i < ps.length; i++)
            m[ps[i].name] = palette[i % palette.length];
        colorMap = m;
    }

    function colorFor(name) {
        return colorMap[name] || "#585b70";
    }

    // The day currently hovered in the chart, or null. Drives the breakdown
    // list below so it shows that day instead of the 7-day totals.
    readonly property var hoveredDay: (hoverDay >= 0 && week && week.days && hoverDay < week.days.length)
                                      ? week.days[hoverDay] : null

    // Reserve the breakdown list's height for the full 7-day list (always the
    // largest, since a day's projects are a subset) so hovering a day with fewer
    // rows doesn't resize the popup and make it jump.
    readonly property int listRowH: 18
    readonly property int listRowGap: 5
    readonly property int listReservedRows: Math.min(10, (week && week.projects) ? week.projects.length : 0)
    readonly property int listReservedHeight: listReservedRows > 0
        ? listReservedRows * listRowH + (listReservedRows - 1) * listRowGap : 0

    // Same idea for the by-model list — reserve for the 7-day model set (the
    // superset of any single day's) so hovering doesn't resize the popup.
    readonly property int listReservedModelRows: Math.min(6, (week && week.models) ? week.models.length : 0)
    readonly property int listReservedModelHeight: listReservedModelRows > 0
        ? listReservedModelRows * listRowH + (listReservedModelRows - 1) * listRowGap : 0

    function dayLabel(ds) {
        if (!ds) return "";
        var dt = new Date(ds + "T00:00:00");
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][dt.getDay()] + " " + ds.slice(5);
    }

    onPopupOpenChanged: if (popupOpen) loadProc.running = true

    function parseData() {
        if (!usageData) return;
        today = usageData.today || null;
        week = usageData.week || null;
        dateStr = usageData.date || "";
        rebuildColors();
        weekCanvas.requestPaint();
    }

    function fmtCost(c) {
        if (!c || c <= 0) return "$0";
        if (c >= 100) return "$" + Math.round(c);
        if (c >= 10) return "$" + c.toFixed(1);
        return "$" + c.toFixed(2);
    }

    function fmtTokens(t) {
        if (!t) return "0";
        if (t >= 1e6) return (t / 1e6).toFixed(1) + "M";
        if (t >= 1e3) return Math.round(t / 1e3) + "k";
        return "" + Math.round(t);
    }

    // Active agent time, seconds -> "1h05m" / "58m" / "<1m".
    function fmtDur(s) {
        if (!s || s < 60) return s > 0 ? "<1m" : "0m";
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        if (h > 0) return h + "h" + (m < 10 ? "0" : "") + m + "m";
        return m + "m";
    }

    // "claude-opus-4-8" -> "Opus 4.8". Version digits sit either after the
    // family (opus-4-8) or before it (3-5-haiku); date snapshots (>2 digits)
    // are dropped so "opus-4-20250514" reads as "Opus 4".
    function prettyModel(name) {
        if (!name) return "unknown";
        var s = name.toLowerCase();
        if (s.indexOf("synthetic") >= 0) return "synthetic";
        var fam = s.indexOf("opus") >= 0 ? "Opus"
                : s.indexOf("sonnet") >= 0 ? "Sonnet"
                : s.indexOf("haiku") >= 0 ? "Haiku" : "";
        if (!fam) return name;
        var key = fam.toLowerCase();
        var after = s.match(new RegExp(key + "-(\\d+)(?:-(\\d+))?"));
        var before = s.match(new RegExp("(\\d+)-(\\d+)-" + key));
        var ver = "";
        if (after && after[1] && after[1].length <= 2)
            ver = after[1] + (after[2] && after[2].length <= 2 ? "." + after[2] : "");
        else if (before)
            ver = before[1] + "." + before[2];
        return ver ? fam + " " + ver : fam;
    }

    function modelColor(name) {
        var s = (name || "").toLowerCase();
        if (s.indexOf("opus") >= 0) return "#cba6f7";   // mauve
        if (s.indexOf("sonnet") >= 0) return "#89b4fa"; // blue
        if (s.indexOf("haiku") >= 0) return "#a6e3a1";  // green
        return "#585b70";
    }

    Process {
        id: loadProc
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/claude-usage/today"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.usageData = JSON.parse(this.text);
                    root.parseData();
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: root.popupOpen ? 15000 : 60000
        running: true
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
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface {
                anchors.fill: parent
            }

            Flickable {
                anchors.fill: parent
                anchors.margins: 16
                contentWidth: width
                contentHeight: mainCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                    id: mainCol
                    width: parent.width
                    spacing: 12

                    // ── Header ────────────────────────────────────────────
                    Item {
                        width: parent.width
                        height: 24
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰷧"
                                color: Helpers.Colors.accent
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.dateStr
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            }
                        }
                        Components.StatDots {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            boldFirst: true
                            values: [
                                root.fmtCost(root.today ? root.today.totalCost : 0),
                                root.fmtTokens(root.today ? root.today.totalTokens : 0),
                                root.fmtDur(root.today ? root.today.totalActive : 0)
                            ]
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── Today per-project ─────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Today by project"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            font.bold: true
                        }

                        Text {
                            visible: !root.today || root.today.projects.length === 0
                            text: "No usage yet today"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        }

                        Repeater {
                            model: root.today ? root.today.projects : []
                            delegate: Column {
                                id: proj
                                required property var modelData
                                required property int index
                                width: parent.width
                                spacing: 4
                                readonly property color barColor: root.colorFor(modelData.name)
                                readonly property real frac: (root.today && root.today.totalCost > 0)
                                    ? (modelData.cost / root.today.totalCost) : 0

                                Item {
                                    width: parent.width
                                    height: 18
                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: proj.barColor
                                        }
                                        Text {
                                            text: modelData.name || ""
                                            color: Helpers.Colors.textDefault
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    Text {
                                        id: tokText
                                        anchors.right: costText.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.fmtTokens(modelData.tokens)
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }
                                    Text {
                                        anchors.right: tokText.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: " " + root.fmtDur(modelData.active || 0)
                                        color: Qt.rgba(1, 1, 1, 0.4)
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }
                                    Text {
                                        id: costText
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.fmtCost(modelData.cost)
                                        color: Helpers.Colors.textDefault
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                        width: 56
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: 5
                                    Rectangle {
                                        width: parent.width; height: 5; radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                    }
                                    Rectangle {
                                        width: Math.max(0, parent.width * proj.frac)
                                        height: 5; radius: 3
                                        color: proj.barColor
                                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08)
                        visible: root.today && root.today.models && root.today.models.length > 0
                    }

                    // ── Today per-model ───────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 8
                        visible: root.today && root.today.models && root.today.models.length > 0

                        Text {
                            text: "Today by model"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            font.bold: true
                        }

                        Repeater {
                            model: root.today ? root.today.models : []
                            delegate: Column {
                                id: mdl
                                required property var modelData
                                width: parent.width
                                spacing: 4
                                readonly property color barColor: root.modelColor(modelData.name)
                                readonly property real frac: (root.today && root.today.totalTokens > 0)
                                    ? (modelData.tokens / root.today.totalTokens) : 0

                                Item {
                                    width: parent.width
                                    height: 18
                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: mdl.barColor
                                        }
                                        Text {
                                            text: root.prettyModel(modelData.name)
                                            color: Helpers.Colors.textDefault
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    Text {
                                        id: mdlTok
                                        anchors.right: mdlCost.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.fmtTokens(modelData.tokens)
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }
                                    Text {
                                        id: mdlCost
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.fmtCost(modelData.cost)
                                        color: Helpers.Colors.textDefault
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                        width: 56
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: 5
                                    Rectangle {
                                        width: parent.width; height: 5; radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                    }
                                    Rectangle {
                                        width: Math.max(0, parent.width * mdl.frac)
                                        height: 5; radius: 3
                                        color: mdl.barColor
                                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── 7-day trend ───────────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 16
                            Text {
                                anchors.left: parent.left
                                text: "Last 7 days"
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                font.bold: true
                            }
                            Components.StatDots {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                values: [
                                    root.fmtCost(root.week ? root.week.totalCost : 0),
                                    root.fmtTokens(root.week ? root.week.totalTokens : 0),
                                    root.fmtDur(root.week ? root.week.totalActive : 0)
                                ]
                            }
                        }

                        Item {
                            width: parent.width
                            height: 82

                            // Geometry shared by the canvas painter and the hover math.
                            readonly property int labelH: 16
                            readonly property int topPad: 16   // room for the cost label
                            readonly property int gap: 8
                            readonly property int n: (root.week && root.week.days) ? root.week.days.length : 0
                            readonly property real bw: n > 0 ? (width - gap * (n - 1)) / n : 0

                            Canvas {
                                id: weekCanvas
                                anchors.fill: parent

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    if (!root.week || !root.week.days) return;

                                    var days = root.week.days;
                                    var n = parent.n;
                                    if (n === 0) return;
                                    var maxC = Math.max(root.week.maxDayCost || 0, 0.01);

                                    var chartH = height - parent.labelH;
                                    var usable = chartH - parent.topPad;
                                    var gap = parent.gap;
                                    var bw = parent.bw;

                                    ctx.font = "11px '" + AppConfig.Config.theme.fontFamily + "'";
                                    ctx.textAlign = "center";
                                    var names = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];

                                    for (var i = 0; i < n; i++) {
                                        var d = days[i];
                                        var x = i * (bw + gap);
                                        var isToday = (i === n - 1);
                                        var hovered = (i === root.hoverDay);

                                        // hover backdrop for the whole column
                                        if (hovered) {
                                            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.06);
                                            roundRect(ctx, x - 2, 0, bw + 4, chartH, 4);
                                            ctx.fill();
                                        }

                                        var totalH = Math.max(d.cost > 0 ? 2 : 0, (d.cost / maxC) * usable);
                                        var segs = d.projects || [];

                                        if (d.cost <= 0) {
                                            // empty-day stub
                                            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.06);
                                            roundRect(ctx, x, chartH - 2, bw, 2, 1);
                                            ctx.fill();
                                        } else if (segs.length === 0) {
                                            ctx.fillStyle = Qt.rgba(0.54, 0.71, 0.98, 0.45);
                                            roundRectTop(ctx, x, chartH - totalH, bw, totalH, 3);
                                            ctx.fill();
                                        } else {
                                            // Stacked colored segments, largest at the bottom.
                                            var yCursor = chartH;
                                            for (var s = 0; s < segs.length; s++) {
                                                var seg = segs[s];
                                                var sh = (seg.cost / maxC) * usable;
                                                if (sh <= 0) continue;
                                                var top = yCursor - sh;
                                                ctx.globalAlpha = hovered ? 1.0 : 0.9;
                                                ctx.fillStyle = root.colorFor(seg.name);
                                                if (s === 0 && segs.length === 1)
                                                    roundRect(ctx, x, top, bw, sh, 3);
                                                else if (s === segs.length - 1)
                                                    roundRectTop(ctx, x, top, bw, sh, 3);
                                                else
                                                    ctx.fillRect(x, top, bw, sh);
                                                ctx.fill();
                                                yCursor = top;
                                            }
                                            ctx.globalAlpha = 1.0;
                                        }

                                        // cost label above bar
                                        if (d.cost > 0) {
                                            ctx.fillStyle = Qt.rgba(1, 1, 1, (isToday || hovered) ? 0.9 : 0.5);
                                            ctx.fillText(root.fmtCost(d.cost), x + bw / 2, (chartH - totalH) - 5);
                                        }

                                        // weekday label
                                        var dow = new Date(d.date + "T00:00:00").getDay();
                                        ctx.fillStyle = Qt.rgba(1, 1, 1, (isToday || hovered) ? 0.8 : 0.35);
                                        ctx.fillText(names[dow], x + bw / 2, height - 3);
                                    }
                                }

                                function roundRect(ctx, x, y, w, h, r) {
                                    r = Math.min(r, w / 2, h / 2);
                                    ctx.beginPath();
                                    ctx.moveTo(x + r, y);
                                    ctx.lineTo(x + w - r, y);
                                    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
                                    ctx.lineTo(x + w, y + h);
                                    ctx.lineTo(x, y + h);
                                    ctx.lineTo(x, y + r);
                                    ctx.quadraticCurveTo(x, y, x + r, y);
                                    ctx.closePath();
                                }

                                // Rounded top corners only (square base — sits on the axis).
                                function roundRectTop(ctx, x, y, w, h, r) {
                                    r = Math.min(r, w / 2, h);
                                    ctx.beginPath();
                                    ctx.moveTo(x + r, y);
                                    ctx.lineTo(x + w - r, y);
                                    ctx.quadraticCurveTo(x + w, y, x + w, y + r);
                                    ctx.lineTo(x + w, y + h);
                                    ctx.lineTo(x, y + h);
                                    ctx.lineTo(x, y + r);
                                    ctx.quadraticCurveTo(x, y, x + r, y);
                                    ctx.closePath();
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                onPositionChanged: function (mouse) {
                                    var slot = parent.bw + parent.gap;
                                    if (slot <= 0) { root.hoverDay = -1; return; }
                                    var idx = Math.floor(mouse.x / slot);
                                    root.hoverDay = (idx >= 0 && idx < parent.n) ? idx : -1;
                                }
                                onExited: root.hoverDay = -1
                            }

                            onNChanged: weekCanvas.requestPaint()
                            Connections {
                                target: root
                                function onHoverDayChanged() { weekCanvas.requestPaint(); }
                            }

                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── By-project breakdown (7-day total, or hovered day) ─
                    Column {
                        id: byProjCol
                        width: parent.width
                        spacing: 5

                        // Projects to show: the hovered day's, else the 7-day totals.
                        readonly property var listProjects: {
                            var src = root.hoveredDay ? root.hoveredDay.projects
                                                      : (root.week ? root.week.projects : []);
                            return src.length > 10 ? src.slice(0, 10) : src;
                        }

                        // Models for the same scope (hovered day, else 7-day totals).
                        readonly property var listModels: {
                            var src = root.hoveredDay ? (root.hoveredDay.models || [])
                                                      : (root.week ? (root.week.models || []) : []);
                            return src.length > 6 ? src.slice(0, 6) : src;
                        }

                        Item {
                            width: parent.width
                            height: 16
                            Text {
                                anchors.left: parent.left
                                text: root.hoveredDay ? (root.dayLabel(root.hoveredDay.date) + " by project")
                                                      : "7-day by project"
                                color: root.hoveredDay ? Helpers.Colors.accent : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                font.bold: true
                            }
                            Components.StatDots {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !!root.hoveredDay
                                fontSize: AppConfig.Config.theme.popupFontSizeXSmall
                                values: root.hoveredDay
                                    ? [root.fmtCost(root.hoveredDay.cost), root.fmtTokens(root.hoveredDay.tokens), root.fmtDur(root.hoveredDay.active || 0)]
                                    : []
                            }
                        }

                        Item {
                            width: parent.width
                            height: root.listReservedHeight

                            Column {
                                width: parent.width
                                spacing: 5

                                Repeater {
                                    model: byProjCol.listProjects
                                    Item {
                                        required property var modelData
                                        width: parent.width
                                        height: 18
                                        Text {
                                            id: wkCost
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.fmtCost(modelData.cost)
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    width: 70
                                    horizontalAlignment: Text.AlignRight
                                }
                                Text {
                                    id: wkTokens
                                    anchors.right: wkCost.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.fmtTokens(modelData.tokens)
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                    width: 60
                                    horizontalAlignment: Text.AlignRight
                                }
                                Text {
                                    id: wkTime
                                    anchors.right: wkTokens.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: " " + root.fmtDur(modelData.active || 0)
                                    color: Qt.rgba(1, 1, 1, 0.4)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                    width: 56
                                    horizontalAlignment: Text.AlignRight
                                }
                                Rectangle {
                                    id: wkDot
                                    width: 8; height: 8; radius: 4
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: root.colorFor(modelData.name)
                                }
                                Text {
                                    anchors.left: wkDot.right
                                    anchors.leftMargin: 8
                                    anchors.right: wkTime.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name || ""
                                            color: Helpers.Colors.textDefault
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        // ── By-model breakdown (same hovered-day / 7-day scope) ─
                        Item {
                            width: parent.width
                            height: 16
                            visible: byProjCol.listModels.length > 0
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.hoveredDay ? (root.dayLabel(root.hoveredDay.date) + " by model")
                                                      : "7-day by model"
                                color: root.hoveredDay ? Helpers.Colors.accent : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                font.bold: true
                            }
                        }

                        Item {
                            width: parent.width
                            height: root.listReservedModelHeight
                            visible: byProjCol.listModels.length > 0

                            Column {
                                width: parent.width
                                spacing: 5

                                Repeater {
                                    model: byProjCol.listModels
                                    Item {
                                        required property var modelData
                                        width: parent.width
                                        height: 18
                                        Text {
                                            id: mCost
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.fmtCost(modelData.cost)
                                            color: Qt.rgba(1, 1, 1, 0.6)
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            width: 70
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            id: mToks
                                            anchors.right: mCost.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.fmtTokens(modelData.tokens)
                                            color: Qt.rgba(1, 1, 1, 0.45)
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                            width: 60
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Rectangle {
                                            id: mDot
                                            width: 8; height: 8; radius: 4
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: root.modelColor(modelData.name)
                                        }
                                        Text {
                                            anchors.left: mDot.right
                                            anchors.leftMargin: 8
                                            anchors.right: mToks.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.prettyModel(modelData.name)
                                            color: Helpers.Colors.textDefault
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
