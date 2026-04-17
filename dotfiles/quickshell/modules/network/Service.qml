import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property var context
    property bool pinned: false

    IpcHandler {
        target: "network"

        function toggle() {
            root.pinned = !root.pinned;
        }

        function pin() {
            root.pinned = true;
        }

        function unpin() {
            root.pinned = false;
        }
    }
}
