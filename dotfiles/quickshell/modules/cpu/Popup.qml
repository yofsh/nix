import QtQuick
import Quickshell
import "../../helpers" as Helpers
import "../../helpers/Format.js" as Format
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
// Opened by left-clicking the cpu widget. Live system view fed by the qs-daemon
// `procmon/sysprocs` stream:
//   • summary tiles: CPU / memory / swap / load
//   • CPU and memory history graphs, SEEDED from the daemon's always-on ring so
//     they show the past few minutes the moment the popup opens (like network)
//   • top apps by CPU (1-min avg) and by memory, grouped by executable
// The per-process scan only runs while this popup is open; the history is sampled
// cheaply by the daemon at all times.
Item {
    id: root
    property bool popupOpen: false

    implicitWidth: 720
    implicitHeight: 582  // fits 10 process rows per column (8 → 10)

    readonly property int maxHistory: 150

    // Aggregate state
    property int ncpu: 1
    property real memTotalKB: 0
    property real swapTotalKB: 0
    property var cur: ({ u: 0, s: 0, mem: 0, swap: 0, load: 0, memUsedKB: 0, swapUsedKB: 0 })
    property var history: []   // [{u, s, mem, swap}]

    // Per-process state
    property var cpuList: []    // [{name, count, value(per-core %)}]
    property var memList: []    // [{name, count, value(bytes)}]

    // Top-CPU list scale: false = % of total system (sums toward the CPU tile);
    // true = per-core (htop-style, can exceed 100%). Toggled by tapping the header.
    property bool cpuPerCore: false

    // Window for the CPU/Mem lists: false = 1-min average, true = instant (now).
    property bool procNow: false

    readonly property color swapColor: "#9575cd"

    readonly property var cpuRows: buildRows(cpuList, true)
    readonly property var memRows: buildRows(memList, false)

    function prettyName(name) {
        if (!name) return "?";
        return ("" + name).replace(/^\./, "").replace(/-wrappe?d?$/, "");
    }
    function gb(kb) { return (kb / 1048576).toFixed(1); }

    // Resolve an app icon from the executable name (cached per name).
    property var iconCache: ({})
    function iconFor(name) {
        var n = prettyName(name);
        if (root.iconCache[n] !== undefined) return root.iconCache[n];
        var src = "";
        var entry = DesktopEntries.heuristicLookup(n);
        if (entry && entry.icon) src = Quickshell.iconPath(entry.icon, true) || "";
        if (!src) src = Quickshell.iconPath(n.toLowerCase(), true) || "";
        if (!src) src = Quickshell.iconPath("application-x-executable", true) || "";
        root.iconCache[n] = src;
        return src;
    }

    function buildRows(list, isCpu) {
        var arr = list || [];
        // Rank by the active window: instant in "now" mode, else the 1-min avg.
        var items = [];
        for (var i = 0; i < arr.length; i++) {
            var e = arr[i];
            var base = (root.procNow && e.inst !== undefined) ? e.inst : e.value;
            items.push({ e: e, base: base });
        }
        items.sort(function(a, b) { return b.base - a.base; });
        items = items.slice(0, 10);
        var memTotalBytes = root.memTotalKB * 1024;
        var swapOn = root.swapTotalKB > 0;
        function swapOf(e) {
            if (isCpu || !swapOn) return 0;
            return (root.procNow && e.swapInst !== undefined) ? e.swapInst : (e.swap || 0);
        }
        // Memory bars scale to total footprint (rss + swap) so the green(rss) +
        // purple(swap) split is in correct proportion, like the network rx/tx bars.
        var max = 0, maxTotal = 0;
        for (var k = 0; k < items.length; k++) {
            if (items[k].base > max) max = items[k].base;
            var tot = items[k].base + swapOf(items[k].e);
            if (tot > maxTotal) maxTotal = tot;
        }
        if (max <= 0) max = 1;
        if (maxTotal <= 0) maxTotal = 1;
        var out = [];
        for (var j = 0; j < items.length; j++) {
            var e2 = items[j].e;
            var base2 = items[j].base;
            var disp = isCpu ? (root.cpuPerCore ? base2 : base2 / Math.max(1, root.ncpu)) : base2;
            // Memory rows: % of total RAM (shown centered like the count) + swap
            // used, and a green/purple split bar proportional to rss vs swap.
            var pctText = "", swapText = "", swap2 = swapOf(e2);
            if (!isCpu) {
                if (memTotalBytes > 0) pctText = Format.pct(disp / memTotalBytes * 100) + "%";
                if (swap2 > 0) swapText = "⇅ " + Format.bytes(swap2);
            }
            out.push({
                name: prettyName(e2.name),
                icon: iconFor(e2.name),
                count: e2.count || 1,
                frac: base2 / max,
                splitBar: !isCpu,
                memFrac: base2 / maxTotal,
                swapFrac: swap2 / maxTotal,
                valueText: isCpu ? Format.pct(disp) + "%" : Format.bytes(disp),
                pctText: pctText,
                swapText: swapText
            });
        }
        return out;
    }

    function applyLine(d) {
        if (!d) return;
        if (d.seed) {
            root.ncpu = d.ncpu || 1;
            root.memTotalKB = d.memTotalKB || 0;
            root.swapTotalKB = d.swapTotalKB || 0;
            var h = [];
            var arr = d.hist || [];
            for (var i = 0; i < arr.length; i++)
                h.push({ u: arr[i][0], s: arr[i][1], mem: arr[i][2], swap: arr[i][3] });
            root.history = h;
        } else if (d.agg) {
            root.cur = {
                u: d.u, s: d.s, mem: d.mem, swap: d.swap, load: d.load,
                memUsedKB: d.memUsedKB, swapUsedKB: d.swapUsedKB
            };
            var hh = root.history.slice();
            hh.push({ u: d.u, s: d.s, mem: d.mem, swap: d.swap });
            if (hh.length > root.maxHistory) hh.shift();
            root.history = hh;
        } else if (d.proc) {
            root.cpuList = d.cpu || [];
            root.memList = d.mem || [];
        }
    }

    // GraphCards repaint themselves via their `series: root.history` binding
    // (onSeriesChanged → requestPaint), so no root-level repaint is needed.

    onPopupOpenChanged: {
        if (!popupOpen) {
            root.cpuList = [];
            root.memList = [];
            root.history = [];
        }
    }

    Helpers.DaemonStream {
        path: "/procmon/sysprocs"
        active: root.popupOpen
        reconnectMs: 500
        onLine: d => root.applyLine(d)
    }

    // ── one summary tile ──
    component StatTile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property string sub: ""
        property color accent: Helpers.Colors.textDefault
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.04)

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 0

            Components.ThemedText {
                text: tile.label
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
            }
            Components.ThemedText {
                text: tile.value
                color: tile.accent
                font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                font.bold: true
            }
            Components.ThemedText {
                text: tile.sub
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                opacity: 0.85
            }
        }
    }

    // ── one history graph card (mode 0 = cpu user+sys stacked, 1 = mem+swap) ──
    component GraphCard: Rectangle {
        id: gcard
        property string title: ""
        property string valueText: ""
        property color accent: Helpers.Colors.textDefault
        property int mode: 0
        property var series: root.history
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.04)
        onSeriesChanged: gcanvas.requestPaint()

        Row {
            id: ghead
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            spacing: 6
            Components.ThemedText {
                text: gcard.title
                color: gcard.accent
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                font.bold: true
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: gcard.valueText
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
            }
        }

        Canvas {
            id: gcanvas
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: ghead.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 8
            anchors.topMargin: 2
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var h = gcard.series || [];
                var n = h.length;
                if (n === 0) return;
                var slot = width / n;
                var bw = Math.max(1, slot - 1);

                if (gcard.mode === 0) {
                    // stacked bars: system (orange) at the base, user (green) on top
                    for (var i = 0; i < n; i++) {
                        var x = i * slot;
                        var sysH = Math.min(100, h[i].s) / 100 * height;
                        var usrH = Math.min(100, h[i].s + h[i].u) / 100 * height - sysH;
                        if (usrH < 0) usrH = 0;
                        ctx.fillStyle = Helpers.Colors.cpu;
                        ctx.fillRect(x, height - sysH, bw, sysH);
                        ctx.fillStyle = Helpers.Colors.cpuUser;
                        ctx.fillRect(x, height - sysH - usrH, bw, usrH);
                    }
                } else {
                    // memory bars + swap line overlay
                    var mc = Helpers.Colors.memory;
                    ctx.fillStyle = Qt.rgba(mc.r, mc.g, mc.b, 0.7);
                    for (var a = 0; a < n; a++) {
                        var mh = Math.min(100, h[a].mem) / 100 * height;
                        ctx.fillRect(a * slot, height - mh, bw, mh);
                    }
                    ctx.beginPath();
                    for (var b = 0; b < n; b++) {
                        var sy = height - Math.min(100, h[b].swap) / 100 * height;
                        var cx = b * slot + bw / 2;
                        if (b === 0) ctx.moveTo(cx, sy); else ctx.lineTo(cx, sy);
                    }
                    ctx.strokeStyle = root.swapColor;
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                }
            }
        }
    }

    // ── one process row ──
    // CPU rows: single-color usage bar + bold value. Memory rows: a split bar
    // (green rss + purple swap, proportional like the network rx/tx bars), the
    // % of RAM centered next to the ×count, and the swap amount as a purple
    // sub-line under the bold memory value.
    component ProcRow: Item {
        id: pr
        property string pname: ""
        property string iconSrc: ""
        property int count: 1
        property string valueText: ""
        property string pctText: ""
        property string swapText: ""
        property real frac: 0
        property bool splitBar: false
        property real memFrac: 0
        property real swapFrac: 0
        property color barColor: "white"
        height: 26

        Rectangle { anchors.fill: parent; radius: 4; color: Qt.rgba(1, 1, 1, 0.04) }

        // cpu: single bar sized by frac
        Rectangle {
            visible: !pr.splitBar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, Math.min(1, pr.frac)) * parent.width
            radius: 4
            color: Qt.rgba(pr.barColor.r, pr.barColor.g, pr.barColor.b, 0.22)
            Behavior on width { NumberAnimation { duration: 250 } }
        }
        // memory: total (rss+swap) bar split into green(rss) + purple(swap)
        Rectangle {
            id: splitFill
            visible: pr.splitBar
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            radius: 4
            clip: true
            color: "transparent"
            width: Math.max(0, Math.min(1, pr.memFrac + pr.swapFrac)) * parent.width
            Behavior on width { NumberAnimation { duration: 250 } }
            Row {
                anchors.fill: parent
                Rectangle {
                    width: (pr.memFrac + pr.swapFrac) > 0
                        ? splitFill.width * (pr.memFrac / (pr.memFrac + pr.swapFrac)) : 0
                    height: parent.height
                    color: Qt.rgba(pr.barColor.r, pr.barColor.g, pr.barColor.b, 0.22)
                }
                Rectangle {
                    width: (pr.memFrac + pr.swapFrac) > 0
                        ? splitFill.width * (pr.swapFrac / (pr.memFrac + pr.swapFrac)) : 0
                    height: parent.height
                    color: Qt.rgba(root.swapColor.r, root.swapColor.g, root.swapColor.b, 0.32)
                }
            }
        }

        Image {
            id: pIcon
            anchors.left: parent.left
            anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            sourceSize.width: 16
            sourceSize.height: 16
            smooth: true
            source: pr.iconSrc
            visible: pr.iconSrc !== ""
        }
        Column {
            id: valueCol
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Components.ThemedText {
                anchors.right: parent.right
                text: pr.valueText
                color: pr.barColor
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                font.bold: true
            }
            Components.ThemedText {
                anchors.right: parent.right
                visible: pr.swapText !== ""
                text: pr.swapText
                color: root.swapColor
                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
            }
        }
        Components.ThemedText {
            id: cntT
            visible: pr.count > 1
            anchors.right: valueCol.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "×" + pr.count
            muted: true
            opacity: 0.7
            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
        }
        // % of RAM — vertically centered, mirroring the ×count placement
        Components.ThemedText {
            id: pctT
            visible: pr.pctText !== ""
            anchors.right: cntT.visible ? cntT.left : valueCol.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: pr.pctText
            muted: true
            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
        }
        Components.ThemedText {
            anchors.left: pIcon.visible ? pIcon.right : parent.left
            anchors.leftMargin: pIcon.visible ? 7 : 10
            anchors.right: pctT.visible ? pctT.left : (cntT.visible ? cntT.left : valueCol.left)
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: pr.pname
            elide: Text.ElideRight
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
        }
    }

    // ── one process column ──
    component ProcColumn: Column {
        id: pcol
        property string title: ""
        property string hint: ""
        property color accentColor: "white"
        property var rows: []
        property bool clickable: false
        signal headerClicked()
        spacing: 3

        Item {
            width: pcol.width
            height: titleRow.implicitHeight
            Row {
                id: titleRow
                spacing: 8
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pcol.title
                    color: pcol.accentColor
                    font.bold: true
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pcol.hint
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: pcol.clickable
                cursorShape: pcol.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: pcol.headerClicked()
            }
        }
        Rectangle { width: pcol.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }
        Components.ThemedText {
            visible: pcol.rows.length === 0
            text: "Sampling…"
            muted: true
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
        }
        Repeater {
            model: pcol.rows
            ProcRow {
                required property var modelData
                width: pcol.width
                pname: modelData.name
                iconSrc: modelData.icon || ""
                count: modelData.count
                valueText: modelData.valueText
                pctText: modelData.pctText || ""
                swapText: modelData.swapText || ""
                frac: modelData.frac
                splitBar: modelData.splitBar || false
                memFrac: modelData.memFrac || 0
                swapFrac: modelData.swapFrac || 0
                barColor: pcol.accentColor
            }
        }
    }

    Components.PopupSurface { anchors.fill: parent }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Header
        Item {
            width: parent.width
            height: 22
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF04C5)   // nf-md-speedometer
                    color: Helpers.Colors.accent
                    font.pixelSize: 18
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "System"
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                    font.bold: true
                }
            }
            // Window toggle (applies to the Top CPU / Top Memory lists)
            Components.ToggleChip {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                label: (root.procNow ? "now" : "1 min avg") + "  ⇄"
                fontSize: AppConfig.Config.theme.popupFontSizeTiny
                onToggled: root.procNow = !root.procNow
            }
        }

        // Summary tiles
        Row {
            width: parent.width
            height: 52
            spacing: 10
            property real tileW: (width - 30) / 4

            StatTile {
                width: parent.tileW; height: parent.height
                label: "CPU"; accent: Helpers.Colors.cpu
                value: Math.round((root.cur.u || 0) + (root.cur.s || 0)) + "%"
                sub: "user " + Math.round(root.cur.u || 0) + " · sys " + Math.round(root.cur.s || 0)
            }
            StatTile {
                width: parent.tileW; height: parent.height
                label: "Memory"; accent: Helpers.Colors.memory
                value: Math.round(root.cur.mem || 0) + "%"
                sub: root.gb(root.cur.memUsedKB || 0) + " / " + root.gb(root.memTotalKB) + " GB"
            }
            StatTile {
                width: parent.tileW; height: parent.height
                label: "Swap"; accent: root.swapColor
                value: root.swapTotalKB > 0 ? Math.round(root.cur.swap || 0) + "%" : "—"
                sub: root.swapTotalKB > 0
                    ? root.gb(root.cur.swapUsedKB || 0) + " / " + root.gb(root.swapTotalKB) + " GB"
                    : "none"
            }
            StatTile {
                width: parent.tileW; height: parent.height
                label: "Load (1m)"; accent: Helpers.Colors.textDefault
                value: (root.cur.load || 0).toFixed(2)
                sub: "of " + root.ncpu + " cores"
            }
        }

        // History graphs
        Row {
            width: parent.width
            height: 116
            spacing: 10
            GraphCard {
                width: (parent.width - 10) / 2; height: parent.height
                title: "CPU"; accent: Helpers.Colors.cpu; mode: 0
                valueText: "~5 min"
            }
            GraphCard {
                width: (parent.width - 10) / 2; height: parent.height
                title: "Memory"; accent: Helpers.Colors.memory; mode: 1
                valueText: "mem + swap"
            }
        }

        // Top processes
        Row {
            width: parent.width
            height: parent.height - 52 - 116 - 24 - 36
            spacing: 16
            ProcColumn {
                width: (parent.width - 16) / 2
                title: "Top CPU"
                hint: root.cpuPerCore ? "1 min · per-core ⇄" : "1 min · % total ⇄"
                accentColor: Helpers.Colors.cpu
                clickable: true
                onHeaderClicked: root.cpuPerCore = !root.cpuPerCore
                rows: root.cpuRows
            }
            ProcColumn {
                width: (parent.width - 16) / 2
                title: "Top Memory"; hint: root.procNow ? "current RSS" : "1 min avg RSS"
                accentColor: Helpers.Colors.memory
                rows: root.memRows
            }
        }
    }
}
