import QtQuick
import Quickshell.Io
import "../config" as AppConfig

// One-shot JSON fetch from the qs-daemon unix socket (or any URL via `url`),
// with the canonical kill-and-restart + stale-response guard built in (see
// CLAUDE.md "Re-triggering a Process"): reload() always fetches the *latest*
// path, in-flight runs are killed, and late responses for an older path are
// discarded instead of overwriting the view.
//
//   Helpers.DaemonFetch {
//       id: fetcher
//       path: "/focus/state"            // http://d<path> on the daemon socket
//       active: root.popupOpen           // gate: fetches only while true
//       intervalMs: 5000                 // optional polling (0 = on demand)
//       onJson: data => root.applyState(data)
//   }
//   // user-driven refetch: fetcher.reload()
//   // reactive path (tabs/day switching): bind `path`; refetch is automatic
Item {
    id: root
    visible: false
    width: 0
    height: 0

    property string path: ""             // daemon route, e.g. "/net/info"
    property string url: ""              // full URL override (skips the socket)
    property bool active: true           // bind to popupOpen for lazy popups
    property bool fetchOnActive: true    // auto-fetch when becoming active
    property int intervalMs: 0           // 0 = no polling
    property string method: "GET"        // or "POST"
    property string body: ""             // POST payload (JSON string)

    readonly property bool busy: proc.running

    signal json(var data)
    signal failed(string text)

    readonly property string _target: url !== "" ? url : path
    property string _requested: ""

    function reload() {
        if (!active || _target === "")
            return;
        _requested = _target;            // snapshot what we're about to fetch
        proc.running = false;            // kill any in-flight run (no-op if idle)
        restartTimer.restart();          // start fresh next tick
    }

    // _target's binding settles during construction ("" -> path), which would
    // fire reload() once per tree build — every hot reload — even with
    // fetchOnActive: false. Fatal for POST/toggle fetchers, so gate on completion.
    property bool _completed: false
    on_TargetChanged: if (_completed) reload()
    onActiveChanged: if (active && fetchOnActive) reload()
    Component.onCompleted: {
        _completed = true;
        if (active && fetchOnActive)
            reload();
    }

    Timer {
        id: restartTimer
        interval: 1
        onTriggered: if (root.active) proc.running = true
    }

    Timer {
        interval: root.intervalMs > 0 ? root.intervalMs : 60000
        running: root.active && root.intervalMs > 0
        repeat: true
        onTriggered: root.reload()
    }

    Process {
        id: proc
        command: {
            var args = ["curl", "-s"];
            if (root.method === "POST")
                args = args.concat(["-X", "POST", "-H", "Content-Type: application/json", "-d", root.body]);
            if (root.url === "")
                args = args.concat(["--unix-socket", AppConfig.Config.daemon.socket, "http://d" + root._requested]);
            else
                args.push(root._requested);
            return args;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (root._requested !== root._target)
                    return;              // navigated on mid-flight — stale, discard
                try {
                    root.json(JSON.parse(this.text));
                } catch (e) {
                    root.failed(this.text);
                }
            }
        }
    }
}
