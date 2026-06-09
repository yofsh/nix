import Quickshell
import Quickshell.Io
import QtQuick
import "../../config" as AppConfig

// Single always-on source for the claude-sessions widget + popup. Consumes the
// daemon's pushed `claude-sessions/stream` (snapshot on connect, then on every
// real change) so the bar reflects a session flipping working↔stopped within
// ~0.3s instead of waiting for a poll. Widget/Popup read context.service.
Scope {
    id: root
    property var context

    property var sessions: []
    property var counts: ({ total: 0, working: 0, idle: 0, attention: 0 })

    function applyLine(line) {
        try {
            var d = JSON.parse(line);
            root.sessions = d.sessions || [];
            root.counts = d.counts || ({ total: 0, working: 0, idle: 0, attention: 0 });
        } catch (e) {}
    }

    Process {
        id: stream
        command: ["curl", "-sN", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/claude-sessions/stream"]
        running: true
        onRunningChanged: if (!running) running = true  // reconnect if the daemon restarts
        stdout: SplitParser {
            onRead: data => root.applyLine(data)
        }
    }
}
