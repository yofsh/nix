import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property var context
    property bool active: false
    property real pingInterval: 1

    IpcHandler {
        target: "ping"

        function toggle() {
            root.active = !root.active;
        }

        function fast() {
            root.pingInterval = 0.5;
            root.active = true;
        }

        function normal() {
            root.pingInterval = 1;
            root.active = true;
        }
    }
}
