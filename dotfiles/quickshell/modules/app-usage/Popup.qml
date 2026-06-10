import QtQuick
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
        ? Math.min(flick.contentHeight + 36, screen.height - barHeight - AppConfig.Config.theme.popupTopGap - 20)
        : flick.contentHeight + 36

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

    // ── Navigation ────────────────────────────────────────────────────────
    // viewMode: "day" (single day) or "week" (rolling 7-day window).
    // navOffset: steps back in time — days in day mode, weeks in week mode.
    property string viewMode: "day"
    property int navOffset: 0
    readonly property bool isLive: viewMode === "day" && navOffset === 0
    readonly property string apiPath: viewMode === "week"
        ? ("/usage/week?offset=" + navOffset)
        : ("/usage/day?offset=" + navOffset)

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

    onPopupOpenChanged: {
        if (popupOpen) {
            // Always reopen on the live current day. usageFetch/historyFetch
            // refetch themselves via their `active` gates (and the apiPath
            // change when we navigated away); focusFetch is always-on, so
            // kick it explicitly.
            viewMode = "day";
            navOffset = 0;
            focusFetch.reload();
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
        dayTimeline.repaint();
    }

    function clock(iso) {
        if (!iso) return "";
        var d = new Date(iso);
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return p(d.getHours()) + ":" + p(d.getMinutes());
    }

    function formatTime(seconds) {
        if (!seconds || seconds <= 0) return "0m";
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + "h " + (m > 0 ? m + "m" : "");
        return m + "m";
    }

    // Usage data for the selected day/week. DaemonFetch provides the canonical
    // kill-and-restart + stale-response-guard fetch: `path` is reactive, so
    // day/week navigation refetches automatically and late responses for an
    // older selection are discarded.
    Helpers.DaemonFetch {
        id: usageFetch
        path: root.apiPath
        active: root.popupOpen
        onJson: data => {
            root.usageData = data;
            root.parseData();
        }
    }

    Helpers.DaemonFetch {
        id: focusFetch
        path: "/focus/today"
        fetchOnActive: false   // driven by the timer below (even while closed) + popup open
        onJson: data => {
            root.focusBlocks = data.blocks || [];
            dayTimeline.repaint();
        }
    }

    Helpers.DaemonFetch {
        id: historyFetch
        path: "/focus/history?limit=10"
        active: root.popupOpen
        onJson: data => {
            root.focusSessions = data.sessions || [];
        }
    }

    Timer {
        // Only the live view auto-refreshes — historical days are static.
        interval: root.popupOpen ? 15000 : 60000
        running: true
        repeat: true
        onTriggered: {
            if (!root.isLive) return;
            usageFetch.reload();
            focusFetch.reload();
            if (root.popupOpen) historyFetch.reload();
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
                id: flick
                anchors.fill: parent
                anchors.margins: 16

                NavHeader {
                    width: parent.width
                    viewMode: root.viewMode
                    navOffset: root.navOffset
                    dateLabel: root.dateLabel
                    rangeLabel: root.rangeLabel
                    totalLabel: root.formatTime(root.totalSeconds)
                    onBack: root.goBack()
                    onForward: root.goForward()
                    onWeekToggled: root.toggleWeek()
                }

                Components.Divider {}

                // ── Week bar chart (week mode only) ───────────────────────
                WeekChart {
                    width: parent.width
                    visible: root.viewMode === "week"
                    weekMax: root.weekMax   // declared before weekDays — see note above
                    weekDays: root.weekDays
                    avgLabel: root.formatTime(root.avgSeconds)
                    fmtTime: root.formatTime
                }

                Components.Divider {
                    visible: root.viewMode === "week"
                }

                // ── Streak / breaks / current window (live day only) ──────
                DayStatus {
                    width: parent.width
                    visible: root.isLive || (root.current !== null && root.current !== undefined)
                    popup: root
                }

                // ── Day Timeline ──────────────────────────────────────────
                DayTimeline {
                    id: dayTimeline
                    width: parent.width
                    visible: root.viewMode === "day" && root.timeline !== null && root.timeline !== undefined
                    timeline: root.timeline
                    segments: root.segments
                    focusBlocks: root.focusBlocks
                    isLive: root.isLive
                }

                Components.Divider {}

                // ── Categories + Top Apps ─────────────────────────────────
                Breakdowns {
                    width: parent.width
                    categories: root.categories
                    topApps: root.topApps
                    fmtTime: root.formatTime
                }

                Components.Divider {
                    visible: root.isLive && root.focusSessions.length > 0
                }

                // ── Focus sessions ────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 5
                    visible: root.isLive && root.focusSessions.length > 0

                    Components.SectionLabel { text: "\uf017 Focus sessions" }

                    Repeater {
                        model: root.focusSessions
                        Row {
                            required property var modelData
                            width: parent.width
                            spacing: 8

                            Components.ThemedText {
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
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Components.ThemedText {
                                text: root.clock(modelData.start)
                                muted: true
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                width: 40
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Components.ThemedText {
                                text: modelData.label && modelData.label.length > 0 ? modelData.label : "Focus"
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                width: parent.width - 16 - 40 - 8 * 3 - 56
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Components.ThemedText {
                                text: root.formatTime(modelData.status === "completed" ? modelData.plannedSeconds : modelData.activeSeconds)
                                color: Qt.rgba(1, 1, 1, 0.6)
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
