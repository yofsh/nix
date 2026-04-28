import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    property var context: null
    readonly property var service: context ? context.service : null
    onServiceChanged: if (service) pickCurrent()

    // ─────────────── Config ───────────────

    // Event display windows (ms)
    readonly property int refreshIntervalMs: 60 * 1000             // how often to query khal + tick
    readonly property int upcomingWindowMs: 30 * 60 * 1000         // full view: icon + title + "in Xm"
    readonly property int compactWindowMs: 3 * 60 * 60 * 1000      // compact view: icon + "1h43m" (no title)
    readonly property int soonThresholdMs: 10 * 60 * 1000          // colors status amber when ≤this

    // Notification
    readonly property int notifyBeforeMs: 2 * 60 * 1000            // fire this long before start
    readonly property int notifyExpireMs: 2 * 60 * 1000            // notification on-screen time
    readonly property string notifyAppName: "Khal"
    readonly property string notifyIconName: "x-office-calendar"
    readonly property string notifyUrgency: "normal"
    readonly property string notifyCategory: "appointment.reminder"
    readonly property string notifyActionLabel: "Open meeting"

    // Visuals
    readonly property int fontSizeIcon: 12
    readonly property int fontSizeText: 11
    readonly property int rowSpacing: 5
    readonly property int horizontalPadding: 6

    // Status colors
    readonly property color inProgressColor: "#f53c3c"             // event running
    readonly property color soonColor: "#ff9800"                   // start ≤soonThresholdMs

    // Meeting link patterns (first match wins)
    readonly property var meetingLinkPatterns: [
        /https:\/\/meet\.google\.com\/[A-Za-z0-9_\-?=&]+/,
        /https:\/\/[A-Za-z0-9.\-]*zoom\.us\/[A-Za-z0-9_\-?=&\/.]+/,
        /https:\/\/teams\.(?:microsoft|live)\.com\/[^\s"<>]+/,
        /https:\/\/[A-Za-z0-9.\-]*webex\.com\/[^\s"<>]+/
    ]

    // ───────────── End config ─────────────

    implicitWidth: row.implicitWidth + horizontalPadding * 2
    implicitHeight: parent ? parent.height : 22

    property var events: []
    property var current: null
    property real now: Date.now()
    property var notifiedUids: ({})
    property string pendingLink: ""

    function calendarInfo(cal) {
        return service ? service.calendarInfo(cal) : service_fallback;
    }
    readonly property var service_fallback: ({ icon: "\uF073", color: Helpers.Colors.textMuted, label: "" })

    function parseTime(s) {
        if (!s) return NaN;
        return new Date(s.replace(' ', 'T')).getTime();
    }

    function extractMeetingLink(desc) {
        if (!desc) return "";
        for (var i = 0; i < meetingLinkPatterns.length; i++) {
            var m = desc.match(meetingLinkPatterns[i]);
            if (m) return m[0];
        }
        return "";
    }

    function formatDuration(ms) {
        var m = Math.round(ms / 60000);
        if (m <= 0) return "now";
        if (m < 60) return m + "m";
        var h = Math.floor(m / 60);
        var mm = m % 60;
        return mm > 0 ? (h + "h" + mm + "m") : (h + "h");
    }

    function pickCurrent() {
        var nowMs = root.now;
        var best = null;
        var bestStart = Infinity;
        var liveUids = {};
        for (var i = 0; i < root.events.length; i++) {
            var e = root.events[i];
            if (e.allDay === true || e["all-day"] === "True") continue;
            var s = parseTime(e.start);
            var en = parseTime(e.end);
            if (isNaN(s) || isNaN(en)) continue;
            if (en <= nowMs) continue;  // already ended

            var uid = e.uid || (e.title + "|" + e.start);
            liveUids[uid] = true;

            // Notify once, within notifyBefore window and before start
            var delta = s - nowMs;
            if (delta > 0 && delta <= notifyBeforeMs && !root.notifiedUids[uid]) {
                root.notifiedUids[uid] = true;
                notifyEvent(e, delta);
            }

            // In-progress events always win over upcoming
            if (s <= nowMs && en > nowMs) {
                best = e;
                continue;
            }
            // Upcoming within the compact window — pick the soonest
            if (delta <= compactWindowMs && s < bestStart) {
                if (!best || parseTime(best.end) <= nowMs) {  // don't override in-progress
                    best = e;
                    bestStart = s;
                }
            }
        }

        // Prune notified uids for events no longer in the window
        var kept = {};
        for (var k in root.notifiedUids) {
            if (liveUids[k]) kept[k] = true;
        }
        root.notifiedUids = kept;

        root.current = best;
    }

    function notifyEvent(e, deltaMs) {
        var link = extractMeetingLink(e.description);
        var title = (e.title || "").trim() || "Calendar event";
        var mins = Math.max(1, Math.round(deltaMs / 60000));
        var body = "Starts in " + mins + "m · " + e.start.split(' ').pop();

        var cmd = ["notify-send",
            "--app-name", notifyAppName,
            "--icon", notifyIconName,
            "--expire-time", String(notifyExpireMs),
            "--urgency", notifyUrgency,
            "--category", notifyCategory];
        if (link) {
            cmd.push("--action", "open=" + notifyActionLabel);
            root.pendingLink = link;
        }
        cmd.push(title, body);

        notifyProc.command = cmd;
        notifyProc.running = true;
    }

    function eventMode() {
        if (!root.current) return "";
        var s = parseTime(root.current.start);
        var en = parseTime(root.current.end);
        if (s <= root.now && en > root.now) return "progress";
        var d = s - root.now;
        if (d <= upcomingWindowMs) return "soon";
        if (d <= compactWindowMs) return "later";
        return "";
    }

    function statusText() {
        if (!root.current) return "";
        var s = parseTime(root.current.start);
        var en = parseTime(root.current.end);
        var mode = eventMode();
        if (mode === "progress") return formatDuration(en - root.now) + " left";
        if (mode === "soon") return "in " + formatDuration(s - root.now);
        return formatDuration(s - root.now);  // "later" — bare duration
    }

    function statusColor() {
        if (!root.current) return Helpers.Colors.textMuted;
        var s = parseTime(root.current.start);
        if (s <= root.now) return inProgressColor;
        if (s - root.now <= soonThresholdMs) return soonColor;
        return Helpers.Colors.textMuted;
    }

    Process {
        id: khalProc
        command: ["khal-agenda"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (Array.isArray(data)) {
                        root.events = data;
                        root.pickCurrent();
                    }
                } catch (e) {
                    console.warn("Khal: parse error", e);
                }
            }
        }
    }

    Timer {
        interval: root.refreshIntervalMs
        running: true
        repeat: true
        triggeredOnStart: false
        onTriggered: {
            root.now = Date.now();
            root.pickCurrent();
            khalProc.running = true;
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: root.rowSpacing

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.current ? root.calendarInfo(root.current.calendar).icon : root.service_fallback.icon
            color: root.current ? root.calendarInfo(root.current.calendar).color : Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: root.fontSizeIcon
        }

        Text {
            visible: root.eventMode() !== "later"
            anchors.verticalCenter: parent.verticalCenter
            text: root.current ? (root.current.title || "").trim() : ""
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: root.fontSizeText
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText()
            color: root.statusColor()
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: root.fontSizeText
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                if (!root.current) return;
                var link = root.extractMeetingLink(root.current.description);
                if (link) {
                    openProc.command = ["xdg-open", link];
                    openProc.running = true;
                }
                return;
            }
            // Left click: toggle agenda popup
            if (root.context)
                root.context.togglePopup();
        }
    }

    Process {
        id: openProc
        command: []
        running: false
    }

    Process {
        id: notifyProc
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var action = this.text.trim();
                if (action === "open" && root.pendingLink) {
                    openProc.command = ["xdg-open", root.pendingLink];
                    openProc.running = true;
                }
                root.pendingLink = "";
            }
        }
    }
}
