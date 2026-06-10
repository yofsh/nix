import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../helpers" as Helpers
import "../../helpers/Format.js" as Format
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
        ? Math.min(bodyFlick.contentHeight + 36, screen.height - barHeight - AppConfig.Config.theme.popupTopGap - 20)
        : bodyFlick.contentHeight + 36

    property var usageData: null
    property var today: null
    property var week: null
    property var limits: null   // subscription rate-limit utilization (5h / weekly / per-model)
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

    onPopupOpenChanged: if (popupOpen) loadFetch.reload()

    function parseData() {
        if (!usageData) return;
        today = usageData.today || null;
        week = usageData.week || null;
        limits = usageData.limits || null;
        dateStr = usageData.date || "";
        rebuildColors();
        weekCanvas.requestPaint();
    }

    // Subscription rate-limit windows -> display rows (overall first, per-model
    // indented as sub-rows; only the windows the endpoint actually reports).
    function limitRows() {
        if (!limits) return [];
        var rows = [];
        if (limits.fiveHour) rows.push({ label: "5-hour", sub: false, w: limits.fiveHour });
        if (limits.sevenDay) rows.push({ label: "Weekly", sub: false, w: limits.sevenDay });
        if (limits.sevenDayOpus) rows.push({ label: "Opus", sub: true, w: limits.sevenDayOpus });
        if (limits.sevenDaySonnet) rows.push({ label: "Sonnet", sub: true, w: limits.sevenDaySonnet });
        return rows;
    }

    // ISO reset timestamp -> "16:30" (today) or "Mon 15:00" (another day), local time.
    function fmtReset(iso) {
        if (!iso) return "";
        var d = new Date(iso);
        if (isNaN(d.getTime())) return "";
        function pad(n) { return (n < 10 ? "0" : "") + n; }
        var hm = d.getHours() + ":" + pad(d.getMinutes());
        if (d.toDateString() === new Date().toDateString()) return hm;
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()] + " " + hm;
    }

    // green < 50% < amber < 80% < red
    function limitColor(pct) {
        if (pct >= 80) return Helpers.Colors.mutedRed;
        if (pct >= 50) return "#ff9800";
        return Helpers.Colors.accent;
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
        var fam = s.indexOf("fable") >= 0 ? "Fable"
                : s.indexOf("mythos") >= 0 ? "Mythos"
                : s.indexOf("opus") >= 0 ? "Opus"
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
        if (s.indexOf("fable") >= 0) return "#fab387";  // peach
        if (s.indexOf("mythos") >= 0) return "#f5c2e7"; // pink
        if (s.indexOf("opus") >= 0) return "#cba6f7";   // mauve
        if (s.indexOf("sonnet") >= 0) return "#89b4fa"; // blue
        if (s.indexOf("haiku") >= 0) return "#a6e3a1";  // green
        return "#585b70";
    }

    Helpers.DaemonFetch {
        id: loadFetch
        path: "/claude-usage/today"
        fetchOnActive: false    // first fetch comes from onPopupOpenChanged / the poll timer
        intervalMs: root.popupOpen ? 15000 : 60000
        onJson: data => {
            root.usageData = data;
            root.parseData();
        }
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

            Components.PopupFlick {
                id: bodyFlick
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                    // ── Header ────────────────────────────────────────────
                    Item {
                        width: parent.width
                        height: 24
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Components.ThemedText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰷧"
                                color: Helpers.Colors.accent
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                            }
                            Components.ThemedText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.dateStr
                                muted: true
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            }
                        }
                        Components.StatDots {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            boldFirst: true
                            values: [
                                Format.cost(root.today ? root.today.totalCost : 0),
                                Format.tokens(root.today ? root.today.totalTokens : 0),
                                root.fmtDur(root.today ? root.today.totalActive : 0)
                            ]
                        }
                    }

                    Components.Divider {}

                    // ── Usage limits (subscription rate windows) ──────────
                    Column {
                        width: parent.width
                        spacing: 8
                        visible: !!root.limits

                        Components.SectionLabel {
                            text: "Usage limits"
                        }

                        Repeater {
                            model: root.limitRows()
                            delegate: Item {
                                required property var modelData
                                width: parent.width
                                height: 18

                                Components.ThemedText {
                                    id: limLabel
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    leftPadding: modelData.sub ? 10 : 0
                                    width: 88
                                    text: (modelData.sub ? "· " : "") + modelData.label
                                    color: modelData.sub ? Qt.rgba(1, 1, 1, 0.5) : Helpers.Colors.textDefault
                                    font.bold: !modelData.sub
                                    elide: Text.ElideRight
                                }

                                Components.ThemedText {
                                    id: limReset
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 72
                                    horizontalAlignment: Text.AlignRight
                                    text: root.fmtReset(modelData.w.resetsAt)
                                    color: Qt.rgba(1, 1, 1, 0.4)
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                }

                                Components.ThemedText {
                                    id: limPct
                                    anchors.right: limReset.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 34
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round(modelData.w.utilization) + "%"
                                    color: root.limitColor(modelData.w.utilization)
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    font.bold: true
                                }

                                Item {
                                    anchors.left: limLabel.right
                                    anchors.leftMargin: 4
                                    anchors.right: limPct.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 6
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                    }
                                    Rectangle {
                                        width: Math.max(0, parent.width * Math.min(1, modelData.w.utilization / 100))
                                        height: parent.height
                                        radius: 3
                                        color: root.limitColor(modelData.w.utilization)
                                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }

                    Components.Divider {
                        visible: !!root.limits
                    }

                    // ── Today per-project ─────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 8

                        Components.SectionLabel {
                            text: "Today by project"
                        }

                        Components.ThemedText {
                            visible: !root.today || root.today.projects.length === 0
                            text: "No usage yet today"
                            muted: true
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
                                        Components.ThemedText {
                                            text: modelData.name || ""
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    Components.ThemedText {
                                        id: tokText
                                        anchors.right: costText.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Format.tokens(modelData.tokens)
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }
                                    Components.ThemedText {
                                        anchors.right: tokText.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: " " + root.fmtDur(modelData.active || 0)
                                        color: Qt.rgba(1, 1, 1, 0.4)
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }
                                    Components.ThemedText {
                                        id: costText
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Format.cost(modelData.cost)
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

                    Components.Divider {
                        visible: root.today && root.today.models && root.today.models.length > 0
                    }

                    // ── Today per-model ───────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 8
                        visible: root.today && root.today.models && root.today.models.length > 0

                        Components.SectionLabel {
                            text: "Today by model"
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
                                        Components.ThemedText {
                                            text: root.prettyModel(modelData.name)
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                    Components.ThemedText {
                                        id: mdlTok
                                        anchors.right: mdlCost.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Format.tokens(modelData.tokens)
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }
                                    Components.ThemedText {
                                        id: mdlCost
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Format.cost(modelData.cost)
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

                    Components.Divider {}

                    // ── 7-day trend ───────────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 16
                            Components.SectionLabel {
                                anchors.left: parent.left
                                text: "Last 7 days"
                            }
                            Components.StatDots {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                values: [
                                    Format.cost(root.week ? root.week.totalCost : 0),
                                    Format.tokens(root.week ? root.week.totalTokens : 0),
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
                                            ctx.fillText(Format.cost(d.cost), x + bw / 2, (chartH - totalH) - 5);
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

                    Components.Divider {}

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
                            Components.SectionLabel {
                                anchors.left: parent.left
                                text: root.hoveredDay ? (root.dayLabel(root.hoveredDay.date) + " by project")
                                                      : "7-day by project"
                                color: root.hoveredDay ? Helpers.Colors.accent : Helpers.Colors.textMuted
                            }
                            Components.StatDots {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !!root.hoveredDay
                                fontSize: AppConfig.Config.theme.popupFontSizeXSmall
                                values: root.hoveredDay
                                    ? [Format.cost(root.hoveredDay.cost), Format.tokens(root.hoveredDay.tokens), root.fmtDur(root.hoveredDay.active || 0)]
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
                                        Components.ThemedText {
                                            id: wkCost
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Format.cost(modelData.cost)
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    width: 70
                                    horizontalAlignment: Text.AlignRight
                                }
                                Components.ThemedText {
                                    id: wkTokens
                                    anchors.right: wkCost.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Format.tokens(modelData.tokens)
                                    color: Qt.rgba(1, 1, 1, 0.45)
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                    width: 60
                                    horizontalAlignment: Text.AlignRight
                                }
                                Components.ThemedText {
                                    id: wkTime
                                    anchors.right: wkTokens.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: " " + root.fmtDur(modelData.active || 0)
                                    color: Qt.rgba(1, 1, 1, 0.4)
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
                                Components.ThemedText {
                                    anchors.left: wkDot.right
                                    anchors.leftMargin: 8
                                    anchors.right: wkTime.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.name || ""
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
                            Components.SectionLabel {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.hoveredDay ? (root.dayLabel(root.hoveredDay.date) + " by model")
                                                      : "7-day by model"
                                color: root.hoveredDay ? Helpers.Colors.accent : Helpers.Colors.textMuted
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
                                        Components.ThemedText {
                                            id: mCost
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Format.cost(modelData.cost)
                                            color: Qt.rgba(1, 1, 1, 0.6)
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            width: 70
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Components.ThemedText {
                                            id: mToks
                                            anchors.right: mCost.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Format.tokens(modelData.tokens)
                                            color: Qt.rgba(1, 1, 1, 0.45)
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
                                        Components.ThemedText {
                                            anchors.left: mDot.right
                                            anchors.leftMargin: 8
                                            anchors.right: mToks.left
                                            anchors.rightMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.prettyModel(modelData.name)
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
