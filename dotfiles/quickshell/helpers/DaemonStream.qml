import QtQuick
import Quickshell.Io
import "../config" as AppConfig

// Long-lived line stream from the qs-daemon unix socket (curl -sN), with
// automatic reconnect on exit. Each line is parsed as JSON and emitted via
// `line`; unparseable lines are ignored (use `rawLine` for plain-text streams).
// Reconnect is delayed (reconnectMs) so a dead daemon doesn't busy-loop curl.
//
//   Helpers.DaemonStream {
//       path: "/net/stream"
//       onLine: data => root.applyDaemonState(data)
//   }
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property string path: ""             // daemon route, e.g. "/net/stream"
    property bool active: true
    property int reconnectMs: 1000

    signal line(var data)
    signal rawLine(string text)

    function _sync() {
        proc.running = active && path !== "";
    }

    onActiveChanged: _sync()
    onPathChanged: {
        proc.running = false;            // drop the old stream; reconnect picks up the new path
        _sync();
    }
    Component.onCompleted: _sync()

    Timer {
        id: reconnectTimer
        interval: root.reconnectMs
        onTriggered: root._sync()
    }

    Process {
        id: proc
        command: ["curl", "-sN", "--unix-socket", AppConfig.Config.daemon.socket, "http://d" + root.path]
        onRunningChanged: {
            if (!running)
                reconnectTimer.restart();
        }
        stdout: SplitParser {
            onRead: data => {
                if (!data)
                    return;
                root.rawLine(data);
                try {
                    root.line(JSON.parse(data.trim()));
                } catch (e) {}
            }
        }
    }
}
