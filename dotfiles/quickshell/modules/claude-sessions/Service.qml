import Quickshell
import QtQuick
import "../../helpers" as Helpers

// Single always-on source for the claude-sessions widget + popup. Consumes the
// daemon's pushed `claude-sessions/stream` (snapshot on connect, then on every
// real change) so the bar reflects a session flipping working↔stopped within
// ~0.3s instead of waiting for a poll. Widget/Popup read context.service.
Scope {
    id: root
    property var context

    property var sessions: []
    property var counts: ({ total: 0, working: 0, idle: 0, attention: 0 })

    function applyLine(d) {
        root.sessions = d.sessions || [];
        root.counts = d.counts || ({ total: 0, working: 0, idle: 0, attention: 0 });
    }

    Helpers.DaemonStream {
        path: "/claude-sessions/stream"
        onLine: d => root.applyLine(d)
    }
}
