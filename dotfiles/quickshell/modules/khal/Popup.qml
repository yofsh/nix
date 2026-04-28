import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

PanelWindow {
    id: root

    property var context: null
    readonly property var service: context ? context.service : null

    // ─────────────── Config ───────────────

    readonly property int spanDays: 14                      // how far forward the popup shows
    readonly property int refreshIntervalMs: 60 * 1000      // auto-refresh while open
    readonly property int popupWidth: 720
    readonly property int popupHeight: 620
    readonly property var defaultCalendar: ({ icon: "\uF073", color: Helpers.Colors.textMuted, label: "" })

    // Status styling
    readonly property color upcomingColor: "#0caf49"        // future events — accent
    readonly property color inProgressColor: "#f53c3c"      // event is currently running
    readonly property color soonColor: "#ff9800"            // starts in <soonThresholdMs — amber
    readonly property color farColor: Qt.rgba(1, 1, 1, 0.25) // starts ≥farThresholdMs away — faded gray
    readonly property real pastOpacity: 0.35                // fade past events

    // Attendee counter colors (tentative counts as unanswered)
    readonly property color attendeeAcceptedColor: "#0caf49"
    readonly property color attendeeDeclinedColor: "#f53c3c"
    readonly property color attendeeUnansweredColor: Qt.rgba(1, 1, 1, 0.45)

    // Time-label color thresholds (how soon the event is starting)
    readonly property int soonThresholdMs: 60 * 60 * 1000         // ≤1h → soonColor
    readonly property int farThresholdMs: 24 * 60 * 60 * 1000     // ≥24h → farColor

    // ───────────── End config ─────────────

    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: popupWidth
    implicitHeight: popupHeight
    visible: popupOpen
    color: "transparent"

    property var events: []
    property bool dataLoaded: false
    property real now: Date.now()

    onPopupOpenChanged: {
        if (popupOpen) loadProc.running = true;
    }

    function calendarInfo(cal) {
        return service ? service.calendarInfo(cal) : defaultCalendar;
    }

    function formatTimeRange(e) {
        if (e.allDay) return "All day";
        var s = e.start.split(' ').pop();
        var en = e.end.split(' ').pop();
        return s + "–" + en;
    }

    function parseTime(s) {
        if (!s) return NaN;
        return new Date(s.replace(' ', 'T')).getTime();
    }

    function eventStatus(e) {
        if (e.allDay) {
            // all-day: compare date only
            var today = todayStr();
            if (e.start.split(' ')[0] < today) return "past";
            if (e.start.split(' ')[0] === today) return "progress";
            return "upcoming";
        }
        var s = parseTime(e.start);
        var en = parseTime(e.end);
        if (isNaN(s) || isNaN(en)) return "upcoming";
        if (en <= now) return "past";
        if (s <= now) return "progress";
        return "upcoming";
    }

    function formatDelta(ms) {
        var totalMin = Math.round(ms / 60000);
        if (totalMin <= 0) return "now";
        var days = Math.floor(totalMin / 1440);
        var hours = Math.floor((totalMin % 1440) / 60);
        var mins = totalMin % 60;
        if (days > 0) return days + "d" + (hours > 0 ? hours + "h" : "");
        if (hours > 0) return hours + "h" + (mins > 0 ? mins + "m" : "");
        return mins + "m";
    }

    function countdownText(e) {
        var status = eventStatus(e);
        if (status === "past") return "";
        if (e.allDay) return status === "progress" ? "today" : "";
        var s = parseTime(e.start);
        var en = parseTime(e.end);
        if (status === "progress") return formatDelta(en - now) + " left";
        return "in " + formatDelta(s - now);
    }

    function statusColor(status) {
        if (status === "progress") return inProgressColor;
        if (status === "upcoming") return upcomingColor;
        return Helpers.Colors.textMuted;
    }

    // Countdown pill color — tiered by how soon the event starts.
    function countdownColor(e) {
        var status = eventStatus(e);
        if (status === "progress") return inProgressColor;
        if (status === "past") return Helpers.Colors.textMuted;
        if (e.allDay) return upcomingColor;
        var delta = parseTime(e.start) - now;
        if (delta <= soonThresholdMs) return soonColor;           // ≤1h — amber
        if (delta >= farThresholdMs) return farColor;             // ≥24h — faded gray
        return upcomingColor;                                     // 1h–24h — green
    }

    function todayStr() {
        var d = new Date();
        return d.getFullYear() + "-"
            + String(d.getMonth() + 1).padStart(2, "0") + "-"
            + String(d.getDate()).padStart(2, "0");
    }

    function tomorrowStr() {
        var d = new Date();
        d.setDate(d.getDate() + 1);
        return d.getFullYear() + "-"
            + String(d.getMonth() + 1).padStart(2, "0") + "-"
            + String(d.getDate()).padStart(2, "0");
    }

    function dayLabel(dateStr) {
        if (dateStr === todayStr()) return "Today";
        if (dateStr === tomorrowStr()) return "Tomorrow";
        var d = new Date(dateStr + "T00:00:00");
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return days[d.getDay()] + ", " + months[d.getMonth()] + " " + d.getDate();
    }

    // Collapse multiple same-day, same-calendar all-day events (e.g. holidays)
    // into one row so noisy calendars don't flood the agenda.
    readonly property bool groupAllDayByCalendar: true

    // Group events by date → [{date, label, items: [...]}]
    property var groupedEvents: {
        var groups = [];
        var byDate = {};
        for (var i = 0; i < events.length; i++) {
            var e = events[i];
            var date = (e.start || "").split(" ")[0];
            if (!date) continue;
            if (!byDate[date]) {
                byDate[date] = { date: date, label: dayLabel(date), items: [] };
                groups.push(byDate[date]);
            }
            byDate[date].items.push(e);
        }
        if (!groupAllDayByCalendar) return groups;

        for (var g = 0; g < groups.length; g++) {
            var items = groups[g].items;
            var byCal = {};
            var order = [];
            var timed = [];
            for (var j = 0; j < items.length; j++) {
                var ev = items[j];
                if (ev.allDay) {
                    if (!byCal[ev.calendar]) {
                        byCal[ev.calendar] = [];
                        order.push(ev.calendar);
                    }
                    byCal[ev.calendar].push(ev);
                } else {
                    timed.push(ev);
                }
            }
            var collapsed = [];
            for (var k = 0; k < order.length; k++) {
                var cal = order[k];
                var evs = byCal[cal];
                if (evs.length === 1) {
                    collapsed.push(evs[0]);
                } else {
                    var titles = evs.map(function(x) { return x.title || "(untitled)"; });
                    collapsed.push({
                        title: titles.join(" · "),
                        start: evs[0].start,
                        end: evs[0].end,
                        calendar: cal,
                        location: "",
                        allDay: true,
                        uid: "group-" + cal + "-" + groups[g].date,
                        description: "",
                        meetingLink: "",
                        attendees: { total: 0, accepted: 0, declined: 0, tentative: 0, needsAction: 0 },
                        grouped: true,
                        groupCount: evs.length
                    });
                }
            }
            groups[g].items = collapsed.concat(timed);
        }
        return groups;
    }

    Process {
        id: loadProc
        command: ["khal-agenda"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (Array.isArray(data)) {
                        root.events = data;
                        root.dataLoaded = true;
                    }
                } catch (e) {
                    console.warn("KhalPopup: parse error", e);
                }
            }
        }
    }

    Timer {
        interval: root.refreshIntervalMs
        running: root.popupOpen
        repeat: true
        onTriggered: loadProc.running = true
    }

    // Tick `now` every 30s so countdowns stay fresh without refetching events.
    Timer {
        interval: 30000
        running: root.popupOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }

    Process {
        id: openProc
        command: []
        running: false
    }

    function openLink(url) {
        if (!url) return;
        openProc.command = ["xdg-open", url];
        openProc.running = true;
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

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                // Header
                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        text: "\uF073"   // fa-calendar
                        color: Helpers.Colors.textDefault
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeIconLarge
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Agenda"
                        color: Helpers.Colors.textDefault
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeMedium
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: parent.width - 220; height: 1 }
                    Text {
                        text: root.events.length + " events · next " + root.spanDays + "d"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                // Empty state
                Text {
                    visible: root.dataLoaded && root.events.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No upcoming events"
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeDefault
                }

                // Scrollable agenda
                ScrollView {
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    Column {
                        width: parent.width
                        spacing: 10

                        Repeater {
                            model: root.groupedEvents

                            Column {
                                required property var modelData
                                width: ScrollView.view ? ScrollView.view.width - 12 : 700
                                spacing: 4

                                // Day header
                                Row {
                                    spacing: 8
                                    Text {
                                        text: modelData.label
                                        color: modelData.date === root.todayStr()
                                            ? Helpers.Colors.textDefault
                                            : Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.fontSizeBody
                                        font.bold: true
                                    }
                                    Text {
                                        text: modelData.items.length + (modelData.items.length === 1 ? " event" : " events")
                                        color: Qt.rgba(1, 1, 1, 0.3)
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                // Events
                                Repeater {
                                    model: modelData.items

                                    Rectangle {
                                        id: eventRow
                                        required property var modelData
                                        property var info: root.calendarInfo(modelData.calendar)
                                        property bool hasLink: modelData.meetingLink !== ""
                                        property bool hovered: false
                                        property string status: root.eventStatus(modelData)
                                        property color statusColor: root.statusColor(status)
                                        property color pillColor: root.countdownColor(modelData)

                                        width: parent.width
                                        height: contentCol.implicitHeight + 12
                                        color: hovered ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.025)
                                        radius: AppConfig.Config.theme.cardRadiusSmall
                                        opacity: status === "past" ? root.pastOpacity : 1.0

                                        // Left calendar color bar
                                        Rectangle {
                                            width: 3
                                            height: parent.height - 8
                                            anchors.left: parent.left
                                            anchors.leftMargin: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: eventRow.info.color
                                            radius: 2
                                        }

                                        Column {
                                            id: contentCol
                                            anchors.left: parent.left
                                            anchors.leftMargin: 14
                                            anchors.right: parent.right
                                            anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2

                                            Row {
                                                width: parent.width
                                                spacing: 8

                                                Text {
                                                    width: 88
                                                    text: root.formatTimeRange(modelData)
                                                    color: Helpers.Colors.textMuted
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                Text {
                                                    text: eventRow.info.icon
                                                    color: eventRow.info.color
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.fontSizeDefault
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                Text {
                                                    width: parent.width - 88 - 24 - countdownPill.implicitWidth - attendeeBadge.implicitWidth - linkIcon.implicitWidth - 40
                                                    text: modelData.title || "(untitled)"
                                                    color: eventRow.status === "past"
                                                        ? Helpers.Colors.textMuted
                                                        : Helpers.Colors.textDefault
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }

                                                Rectangle {
                                                    id: countdownPill
                                                    visible: countdownText.text.length > 0
                                                    implicitWidth: countdownText.implicitWidth + 10
                                                    implicitHeight: countdownText.implicitHeight + 4
                                                    radius: height / 2
                                                    color: Qt.rgba(eventRow.pillColor.r, eventRow.pillColor.g, eventRow.pillColor.b, 0.15)
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Text {
                                                        id: countdownText
                                                        anchors.centerIn: parent
                                                        text: root.countdownText(eventRow.modelData)
                                                        color: eventRow.pillColor
                                                        font.family: AppConfig.Config.theme.fontFamily
                                                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                        font.bold: eventRow.status === "progress"
                                                    }
                                                }

                                                Row {
                                                    id: attendeeBadge
                                                    property var att: modelData.attendees || { total: 0, accepted: 0, declined: 0, tentative: 0, needsAction: 0 }
                                                    property int unanswered: att.needsAction + att.tentative
                                                    visible: att.total > 1
                                                    spacing: 6
                                                    anchors.verticalCenter: parent.verticalCenter

                                                    Row {
                                                        spacing: 2
                                                        visible: attendeeBadge.att.accepted > 0
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Text {
                                                            text: "\uF00C"  // fa-check
                                                            color: root.attendeeAcceptedColor
                                                            font.family: AppConfig.Config.theme.fontFamily
                                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                        }
                                                        Text {
                                                            text: "" + attendeeBadge.att.accepted
                                                            color: root.attendeeAcceptedColor
                                                            font.family: AppConfig.Config.theme.fontFamily
                                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                        }
                                                    }
                                                    Row {
                                                        spacing: 2
                                                        visible: attendeeBadge.att.declined > 0
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Text {
                                                            text: "\uF00D"  // fa-times
                                                            color: root.attendeeDeclinedColor
                                                            font.family: AppConfig.Config.theme.fontFamily
                                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                        }
                                                        Text {
                                                            text: "" + attendeeBadge.att.declined
                                                            color: root.attendeeDeclinedColor
                                                            font.family: AppConfig.Config.theme.fontFamily
                                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                        }
                                                    }
                                                    Row {
                                                        spacing: 2
                                                        visible: attendeeBadge.unanswered > 0
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        Text {
                                                            text: "\uF128"  // fa-question
                                                            color: root.attendeeUnansweredColor
                                                            font.family: AppConfig.Config.theme.fontFamily
                                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                        }
                                                        Text {
                                                            text: "" + attendeeBadge.unanswered
                                                            color: root.attendeeUnansweredColor
                                                            font.family: AppConfig.Config.theme.fontFamily
                                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                        }
                                                    }
                                                }

                                                Text {
                                                    id: linkIcon
                                                    visible: eventRow.hasLink
                                                    text: "\uF08E"  // fa-external-link
                                                    color: eventRow.hovered ? Helpers.Colors.textDefault : Qt.rgba(1, 1, 1, 0.35)
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            // Location row
                                            Text {
                                                visible: modelData.location && modelData.location.length > 0
                                                width: parent.width
                                                text: "\uF041  " + modelData.location   // fa-map-marker
                                                color: Qt.rgba(1, 1, 1, 0.45)
                                                font.family: AppConfig.Config.theme.fontFamily
                                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                elide: Text.ElideRight
                                            }

                                            // Short description (gray)
                                            Text {
                                                visible: modelData.description && modelData.description.length > 0
                                                width: parent.width
                                                text: modelData.description
                                                color: Qt.rgba(1, 1, 1, 0.4)
                                                font.family: AppConfig.Config.theme.fontFamily
                                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: eventRow.hasLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onEntered: eventRow.hovered = true
                                            onExited: eventRow.hovered = false
                                            onClicked: if (eventRow.hasLink) root.openLink(modelData.meetingLink)
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
