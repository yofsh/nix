pragma Singleton
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool networkPinned: false
    property bool pingActive: false
    property real pingInterval: 1
    property bool sensorsPopupOpen: false
    property bool batteryPopupOpen: false
    property bool wallpaperPopupOpen: false
    property bool weatherPopupOpen: false
    property bool systemPopupOpen: false

    function openWallpaperPopup() {
        root.wallpaperPopupOpen = true;
    }

    function closeWallpaperPopup() {
        root.wallpaperPopupOpen = false;
    }

    IpcHandler {
        target: "network"

        function toggle() {
            root.networkPinned = !root.networkPinned;
        }

        function pin() {
            root.networkPinned = true;
        }

        function unpin() {
            root.networkPinned = false;
        }
    }

    IpcHandler {
        target: "ping"

        function toggle() {
            root.pingActive = !root.pingActive;
        }

        function fast() {
            root.pingInterval = 0.5;
            if (!root.pingActive) root.pingActive = true;
        }

        function normal() {
            root.pingInterval = 1;
            if (!root.pingActive) root.pingActive = true;
        }
    }

    IpcHandler {
        target: "sensors"

        function toggle() {
            root.sensorsPopupOpen = !root.sensorsPopupOpen;
        }
    }

    IpcHandler {
        target: "battery"

        function toggle() {
            root.batteryPopupOpen = !root.batteryPopupOpen;
        }
    }

    IpcHandler {
        target: "weather"

        function toggle() {
            root.weatherPopupOpen = !root.weatherPopupOpen;
        }
    }

    IpcHandler {
        target: "system"

        function toggle() {
            root.systemPopupOpen = !root.systemPopupOpen;
        }
    }

    IpcHandler {
        target: "wallpaper"

        function toggle() {
            root.wallpaperPopupOpen = !root.wallpaperPopupOpen;
        }

        function open() {
            root.openWallpaperPopup();
        }

        function close() {
            root.closeWallpaperPopup();
        }
    }
}
