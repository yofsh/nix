pragma Singleton
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool networkPinned: false
    property bool pingActive: false
    property bool wallpaperPopupOpen: false

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
