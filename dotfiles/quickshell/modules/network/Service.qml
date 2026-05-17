import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    property var context
    property bool pinned: false

    IpcHandler {
        target: "network"

        // Legacy inline-expansion pin (kept for any existing bindings)
        function toggle() {
            root.pinned = !root.pinned;
        }

        function pin() {
            root.pinned = true;
        }

        function unpin() {
            root.pinned = false;
        }

        // Popup controls — delegate to the per-screen widget so the popup
        // tracks the active screen the user is on.
        function open() {
            if (root.context) root.context.openPopup();
        }

        function close() {
            if (root.context) root.context.closePopup();
        }

        function togglePopup() {
            if (root.context) root.context.togglePopup();
        }
    }
}
