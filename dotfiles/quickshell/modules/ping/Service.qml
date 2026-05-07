import Quickshell
import Quickshell.Io
import QtQuick
import "../../helpers" as Helpers

Scope {
    id: root

    property var context
    property var config: Helpers.ModuleConfig.resolve("ping")
    property bool active: config.defaultActive
    property real pingInterval: config.interval

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
