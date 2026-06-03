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

    implicitWidth: 520
    implicitHeight: screen
        ? Math.min(mainCol.implicitHeight + 36, screen.height - barHeight - AppConfig.Config.theme.popupTopGap - 20)
        : mainCol.implicitHeight + 36

    property var usageData: null
    property var categories: []
    property var topApps: []
    property var current: null
    property int totalSeconds: 0
    property int streakSeconds: 0
    property string streakSince: ""
    property bool onBreak: false
    property int breakCount: 0
    property var lastBreak: null
    property string dateStr: ""
    property string dateLabel: ""
    property var timeline: null
    property var focusBlocks: []
    property var focusSessions: []
    property var segments: []
    property int hoverIdx: -1
    property real hoverX: 0

    // ── Navigation ────────────────────────────────────────────────────────
    // viewMode: "day" (single day) or "week" (rolling 7-day window).
    // navOffset: steps back in time — days in day mode, weeks in week mode.
    property string viewMode: "day"
    property int navOffset: 0
    readonly property bool isLive: viewMode === "day" && navOffset === 0
    readonly property string apiUrl: viewMode === "week"
        ? ("http://d/usage/week?offset=" + navOffset)
        : ("http://d/usage/day?offset=" + navOffset)

    // Week-view data. weekMax is set explicitly in parseData *before* weekDays so
    // the bar delegates never read a stale max on first build (which caused bars
    // to flash too tall and then animate down to size).
    property var weekDays: []
    property string rangeLabel: ""
    property int avgSeconds: 0
    property int weekMax: 1

    function goBack() { navOffset += 1; }
    function goForward() { if (navOffset > 0) navOffset -= 1; }
    function toggleWeek() {
        viewMode = (viewMode === "week") ? "day" : "week";
        navOffset = 0;
    }

    // Robust fetch. `requestedUrl` is the URL the (re)started fetch is for.
    // reload() always kills any in-flight curl and restarts on the next tick for
    // the latest URL — so a fast earlier fetch can never win, and there is no
    // queue that could deadlock. The stale-response guard (requestedUrl vs
    // apiUrl) is a second line of defence against showing the wrong day.
    property string requestedUrl: ""

    function reload() {
        if (!popupOpen) return;
        requestedUrl = apiUrl;
        loadProc.running = false;   // stop any in-flight fetch (no-op if idle)
        restartTimer.restart();     // start fresh next tick with the latest URL
    }

    Timer {
        id: restartTimer
        interval: 1
        onTriggered: if (root.popupOpen) loadProc.running = true
    }

    onApiUrlChanged: reload()

    onPopupOpenChanged: {
        if (popupOpen) {
            // Always reopen on the live current day.
            viewMode = "day";
            navOffset = 0;
            reload();
            loadFocusProc.running = true;
            loadFocusHistoryProc.running = true;
        }
    }

    function parseData() {
        if (!usageData) return;
        categories = usageData.categories || [];
        topApps = usageData.topApps || [];
        totalSeconds = usageData.totalSeconds || 0;

        if (usageData.mode === "week") {
            var dd = usageData.days || [];
            var m = 1;
            for (var i = 0; i < dd.length; i++)
                m = Math.max(m, (dd[i] && dd[i].seconds) || 0);
            weekMax = m;        // set before weekDays so delegates build at right size
            weekDays = dd;
            rangeLabel = usageData.rangeLabel || "";
            avgSeconds = usageData.avgSeconds || 0;
            current = null;
            timeline = null;
            segments = [];
            return;
        }

        current = usageData.current || null;
        streakSeconds = usageData.streakSeconds || 0;
        streakSince = usageData.streakSince || "";
        onBreak = !!usageData.onBreak;
        breakCount = usageData.breakCount || 0;
        lastBreak = usageData.lastBreak || null;
        dateStr = usageData.date || "";
        dateLabel = usageData.dateLabel || "";
        timeline = usageData.timeline || null;
        segments = (timeline && timeline.segments) ? timeline.segments : [];
        timelineCanvas.requestPaint();
    }

    function clock(iso) {
        if (!iso) return "";
        var d = new Date(iso);
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return p(d.getHours()) + ":" + p(d.getMinutes());
    }

    // HH:MM from seconds-since-midnight (timeline segment coords).
    function hms(sec) {
        var h = Math.floor(sec / 3600);
        var m = Math.floor((sec % 3600) / 60);
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return p(h) + ":" + p(m);
    }

    function formatTime(seconds) {
        if (!seconds || seconds <= 0) return "0m";
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + "h " + (m > 0 ? m + "m" : "");
        return m + "m";
    }

    Process {
        id: loadProc
        // Bound to requestedUrl (not apiUrl) so the command only changes when
        // reload() decides to fetch — never mid-flight under the running curl.
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, root.requestedUrl]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                // Discard a stale response — the user navigated away while it ran.
                if (root.requestedUrl !== root.apiUrl) return;
                try {
                    root.usageData = JSON.parse(this.text);
                    root.parseData();
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadFocusProc
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/focus/today"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    root.focusBlocks = d.blocks || [];
                    timelineCanvas.requestPaint();
                } catch (e) {}
            }
        }
    }

    Process {
        id: loadFocusHistoryProc
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/focus/history?limit=10"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    root.focusSessions = d.sessions || [];
                } catch (e) {}
            }
        }
    }

    Timer {
        // Only the live view auto-refreshes — historical days are static.
        interval: root.popupOpen ? 15000 : 60000
        running: true
        repeat: true
        onTriggered: {
            if (!root.isLive) return;
            reload();
            loadFocusProc.running = true;
            if (root.popupOpen) loadFocusHistoryProc.running = true;
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
                        height: 26

                        // Left: title + day/week navigation.
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                text: ""
                                color: Helpers.Colors.accent
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // ◀ go back in time (always available)
                            Text {
                                text: ""
                                width: 26; height: 24
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                color: navBackHover.hovered ? Helpers.Colors.accent : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                                HoverHandler { id: navBackHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.goBack() }
                            }

                            Text {
                                // Fixed width keeps the ▶ arrow from shifting as the
                                // label changes ("Today" → "Yesterday" → "May 23 – 29").
                                width: 132
                                text: root.viewMode === "week" ? root.rangeLabel : root.dateLabel
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            // ▶ go forward (disabled at the live edge)
                            Text {
                                text: ""
                                width: 26; height: 24
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                opacity: root.navOffset > 0 ? 1 : 0.25
                                color: navFwdHover.hovered && root.navOffset > 0 ? Helpers.Colors.accent : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                                HoverHandler { id: navFwdHover; enabled: root.navOffset > 0; cursorShape: Qt.PointingHandCursor }
                                TapHandler { enabled: root.navOffset > 0; onTapped: root.goForward() }
                            }
                        }

                        // Right: total + day/week toggle.
                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Text {
                                text: root.formatTime(root.totalSeconds)
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Rectangle {
                                width: toggleText.implicitWidth + 16
                                height: 20
                                radius: 10
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.viewMode === "week" ? Qt.rgba(Helpers.Colors.accent.r, Helpers.Colors.accent.g, Helpers.Colors.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
                                border.width: 1
                                border.color: root.viewMode === "week" ? Helpers.Colors.accent : Qt.rgba(1, 1, 1, 0.12)

                                Text {
                                    id: toggleText
                                    anchors.centerIn: parent
                                    text: "7 days"
                                    color: root.viewMode === "week" ? Helpers.Colors.accent : Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                    font.bold: root.viewMode === "week"
                                }

                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.toggleWeek() }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── Week bar chart (week mode only) ───────────────────
                    Column {
                        width: parent.width
                        spacing: 10
                        visible: root.viewMode === "week"

                        Row {
                            width: parent.width
                            spacing: 8
                            Text {
                                text: "Daily avg"
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.formatTime(root.avgSeconds)
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            id: weekBars
                            width: parent.width
                            height: 110
                            readonly property real gap: 8
                            readonly property real colW: (width - gap * 6) / 7

                            Repeater {
                                model: root.weekDays
                                delegate: Column {
                                    required property var modelData
                                    required property int index
                                    width: weekBars.colW
                                    height: weekBars.height
                                    spacing: 4
                                    x: index * (weekBars.colW + weekBars.gap)

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.seconds > 0 ? root.formatTime(modelData.seconds) : ""
                                        color: Qt.rgba(1, 1, 1, 0.5)
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                    }

                                    // Category-segmented bar. Total height ∝ the
                                    // day's total vs. the week's busiest day; each
                                    // segment is a category, largest at the bottom
                                    // (backend sorts cats ascending). No grow
                                    // animation — bars appear at final size.
                                    Item {
                                        id: barArea
                                        width: parent.width
                                        height: parent.height - 36

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            width: parent.width * 0.62
                                            height: barArea.height * ((modelData.seconds || 0) / root.weekMax)
                                            radius: 4
                                            clip: true
                                            color: modelData.seconds > 0 ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                                            Column {
                                                anchors.fill: parent
                                                Repeater {
                                                    model: modelData.cats || []
                                                    delegate: Rectangle {
                                                        required property var modelData
                                                        width: parent.width
                                                        height: barArea.height * ((modelData.seconds || 0) / root.weekMax)
                                                        color: modelData.color || "#585b70"
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData.label || ""
                                        color: modelData.today ? Helpers.Colors.accent : Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                        font.bold: modelData.today
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08)
                        visible: root.viewMode === "week"
                    }

                    // ── Time without break ───────────────────────────────
                    Row {
                        width: parent.width
                        spacing: 8
                        visible: root.isLive

                        Text {
                            text: root.onBreak ? "" : ""
                            color: {
                                if (root.onBreak) return Helpers.Colors.textMuted;
                                if (root.streakSeconds >= 4500) return Helpers.Colors.mutedRed;
                                if (root.streakSeconds >= 2700) return "#ffb74d";
                                return Helpers.Colors.accent;
                            }
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.onBreak ? "On a break" : "Time without break"
                            color: Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item { width: 1; height: 1 }
                        Text {
                            visible: !root.onBreak
                            text: root.formatTime(root.streakSeconds) + (root.streakSince ? "  ·  since " + root.clock(root.streakSince) : "")
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // ── Breaks today ─────────────────────────────────────
                    Row {
                        width: parent.width
                        spacing: 8
                        visible: root.isLive && root.breakCount > 0

                        Text {
                            text: "" // coffee cup
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.breakCount + (root.breakCount === 1 ? " break today" : " breaks today")
                            color: Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item { width: 1; height: 1 }
                        Text {
                            visible: root.lastBreak !== null
                            text: {
                                if (!root.lastBreak) return "";
                                var dur = root.formatTime(root.lastBreak.seconds);
                                if (root.lastBreak.ongoing)
                                    return "current " + dur + (root.lastBreak.since ? "  ·  since " + root.clock(root.lastBreak.since) : "");
                                return "last " + dur + (root.lastBreak.since ? "  ·  at " + root.clock(root.lastBreak.since) : "");
                            }
                            color: root.lastBreak && root.lastBreak.ongoing ? Helpers.Colors.accent : Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // ── Current window ────────────────────────────────────
                    Row {
                        width: parent.width
                        spacing: 8
                        visible: root.current !== null && root.current !== undefined

                        Rectangle {
                            width: 3; height: 34; radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: {
                                if (!root.current) return Helpers.Colors.textMuted;
                                var cats = root.categories;
                                for (var i = 0; i < cats.length; i++)
                                    if (cats[i].name === root.current.category) return cats[i].color;
                                return Helpers.Colors.textMuted;
                            }
                        }

                        Column {
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: root.current ? (root.current["class"] || "") + "  " + (root.current.category || "") + " · " + (root.current.subcategory || "") : ""
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                            }
                            Text {
                                width: mainCol.width - 24
                                text: root.current ? ((root.current.title || "").length > 70 ? (root.current.title || "").substring(0, 70) + "…" : (root.current.title || "")) : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ── Day Timeline ──────────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 2
                        visible: root.viewMode === "day" && root.timeline !== null && root.timeline !== undefined

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
                                            width: 8; height: 8; radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: tlTip.seg ? tlTip.seg.col : "transparent"
                                        }
                                        Text {
                                            text: tlTip.seg ? (tlTip.seg.cat + "  ·  " + tlTip.seg.sub) : ""
                                            color: Helpers.Colors.textDefault
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            font.bold: true
                                        }
                                    }
                                    Text {
                                        text: tlTip.seg ? (tlTip.seg.cls + "   " + root.hms(tlTip.seg.s) + "–" + root.hms(tlTip.seg.e)) : ""
                                        color: Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── Categories ────────────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 10

                        Repeater {
                            model: root.categories
                            delegate: Column {
                                required property var modelData
                                width: parent.width
                                spacing: 4

                                Item {
                                    width: parent.width
                                    height: 22

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        Text {
                                            text: modelData.icon || ""
                                            color: modelData.color || Helpers.Colors.textMuted
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeDefault
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: modelData.name || ""
                                            color: modelData.color || Helpers.Colors.textDefault
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    Text {
                                        anchors.right: catPctText.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.formatTime(modelData.seconds)
                                        color: Qt.rgba(1, 1, 1, 0.6)
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }
                                    Text {
                                        id: catPctText
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: (modelData.percent || 0) + "%"
                                        color: Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                        width: 42
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                Item {
                                    width: parent.width
                                    height: 8

                                    Rectangle {
                                        width: Math.max(0, parent.width * ((modelData.percent || 0) / 100)) + 6
                                        height: 12; x: -3; y: -2
                                        radius: 6
                                        color: modelData.color || "#585b70"
                                        opacity: 0.1
                                    }

                                    Rectangle {
                                        width: parent.width
                                        height: 5; y: 1
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                    }

                                    Rectangle {
                                        width: Math.max(0, parent.width * ((modelData.percent || 0) / 100))
                                        height: 5; y: 1
                                        radius: 3

                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: modelData.color || "#585b70" }
                                            GradientStop { position: 1.0; color: Qt.darker(modelData.color || "#585b70", 1.5) }
                                        }

                                        Rectangle {
                                            width: parent.width; height: 1
                                            radius: 1; color: "#ffffff"; opacity: 0.15
                                        }

                                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    }
                                }

                                Repeater {
                                    model: modelData.subcategories || []
                                    Row {
                                        required property var modelData
                                        width: parent.width
                                        spacing: 6

                                        Item { width: 20; height: 1 }

                                        Text {
                                            text: modelData.icon || ""
                                            color: Qt.rgba(1, 1, 1, 0.35)
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            width: 18
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: modelData.name || ""
                                            color: Qt.rgba(1, 1, 1, 0.5)
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            width: 120
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: root.formatTime(modelData.seconds)
                                            color: Helpers.Colors.textMuted
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Text {
                                            text: (modelData.percent || 0) + "%"
                                            color: Qt.rgba(1, 1, 1, 0.2)
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                    // ── Top Apps ──────────────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 5

                        Text {
                            text: "Top Apps"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            font.bold: true
                        }

                        Repeater {
                            model: root.topApps.length > 5 ? root.topApps.slice(0, 5) : root.topApps
                            Row {
                                required property var modelData
                                width: parent.width
                                spacing: 10

                                Text {
                                    text: modelData["class"] || ""
                                    color: Helpers.Colors.textDefault
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    width: 160
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.formatTime(modelData.seconds)
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.category || ""
                                    color: Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08)
                        visible: root.isLive && root.focusSessions.length > 0
                    }

                    // ── Focus sessions ────────────────────────────────────
                    Column {
                        width: parent.width
                        spacing: 5
                        visible: root.isLive && root.focusSessions.length > 0

                        Text {
                            text: "\uf017 Focus sessions"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            font.bold: true
                        }

                        Repeater {
                            model: root.focusSessions
                            Row {
                                required property var modelData
                                width: parent.width
                                spacing: 8

                                Text {
                                    width: 16
                                    horizontalAlignment: Text.AlignHCenter
                                    text: {
                                        switch (modelData.status) {
                                        case "completed": return "\uf00c";
                                        case "cancelled": return "\uf00d";
                                        case "interrupted": return "\uf05e";
                                        default: return "\uf017";
                                        }
                                    }
                                    color: {
                                        switch (modelData.status) {
                                        case "completed": return Helpers.Colors.accent;
                                        case "cancelled": return Helpers.Colors.mutedRed;
                                        default: return Helpers.Colors.textMuted;
                                        }
                                    }
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.clock(modelData.start)
                                    color: Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    width: 40
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.label && modelData.label.length > 0 ? modelData.label : "Focus"
                                    color: Helpers.Colors.textDefault
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    width: parent.width - 16 - 40 - 8 * 3 - 56
                                    elide: Text.ElideRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.formatTime(modelData.status === "completed" ? modelData.plannedSeconds : modelData.activeSeconds)
                                    color: Qt.rgba(1, 1, 1, 0.6)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    width: 56
                                    horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
