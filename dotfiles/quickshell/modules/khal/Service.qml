import Quickshell
import Quickshell.Io
import QtQuick
import "../../helpers" as Helpers

Scope {
    id: root

    property var context

    property var calendarMap: ({})

    IpcHandler {
        target: "khal"

        function toggle() {
            if (root.context)
                root.context.togglePopup();
        }

        function open() {
            if (root.context)
                root.context.openPopup();
        }

        function close() {
            if (root.context)
                root.context.closePopup();
        }
    }
    readonly property var defaultCalendar: ({ icon: "\uF073", color: Helpers.Colors.textMuted, label: "" })

    FileView {
        id: calendarMapFile
        path: Qt.resolvedUrl("calendar-map.json").toString().replace("file://", "")
        blockLoading: true
        watchChanges: true
        onFileChanged: { this.reload(); root.loadCalendarMap(); }
    }

    Component.onCompleted: loadCalendarMap()

    function loadCalendarMap() {
        var text = calendarMapFile.text();
        if (!text || text.trim() === "") return;
        try {
            var data = JSON.parse(text);
            var map = {};
            for (var key in data) {
                map[key] = { icon: data[key].icon, color: data[key].color, label: data[key].label || "" };
            }
            root.calendarMap = map;
        } catch (e) {
            console.warn("Khal: failed to parse calendar-map.json", e);
        }
    }

    function calendarInfo(cal) {
        return calendarMap[cal] || defaultCalendar;
    }

    function parseTime(s) {
        if (!s) return NaN;
        return new Date(s.replace(' ', 'T')).getTime();
    }
}
