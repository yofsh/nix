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

    // Pokit Pro multimeter widget
    property bool pokitPopupPinned: false
    property bool pokitPopupDismissed: false
    property string pokitDesiredMode: ""
    property string pokitDesiredRange: ""
    property string pokitTorchRequest: ""
    property string pokitRenameRequest: ""
    property string pokitLoggerCommand: ""
    property int pokitOpRequestId: 0
    property string pokitFlashRequest: ""
    property string pokitPauseRequest: ""
    property string pokitDsoRequest: ""    // "mode|rateHz|samples|nonce"

    function pokitRequest(prop, value) {
        root[prop] = value;
        root.pokitOpRequestId += 1;
    }

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

    IpcHandler {
        target: "pokit"

        function toggle() { root.pokitPopupPinned = !root.pokitPopupPinned; }
        function pin()    { root.pokitPopupPinned = true; }
        function unpin()  { root.pokitPopupPinned = false; }
        function dismiss() { root.pokitPopupDismissed = true; }
        function setMode(m: string) { root.pokitRequest("pokitDesiredMode", m); }
        function setRange(r: string) { root.pokitRequest("pokitDesiredRange", r); }
        function torchOn() { root.pokitRequest("pokitTorchRequest", "on:" + Date.now()); }
        function torchOff() { root.pokitRequest("pokitTorchRequest", "off:" + Date.now()); }
        function flash() { root.pokitRequest("pokitFlashRequest", "" + Date.now()); }
        function rename(n: string) { root.pokitRequest("pokitRenameRequest", n); }
        function loggerStart() { root.pokitRequest("pokitLoggerCommand", "start:" + Date.now()); }
        function loggerStop()  { root.pokitRequest("pokitLoggerCommand", "stop:" + Date.now()); }
        function loggerFetch() { root.pokitRequest("pokitLoggerCommand", "fetch:" + Date.now()); }
        function pause()  { root.pokitRequest("pokitPauseRequest", "pause:" + Date.now()); }
        function resume() { root.pokitRequest("pokitPauseRequest", "resume:" + Date.now()); }
        function togglePause() { root.pokitRequest("pokitPauseRequest", "toggle:" + Date.now()); }
        function dso(mode: string, rateHz: int, samples: int) {
            root.pokitRequest("pokitDsoRequest",
                              mode + "|" + rateHz + "|" + samples + "|" + Date.now());
        }
    }
}
