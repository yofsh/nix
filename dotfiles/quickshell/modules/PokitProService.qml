import QtQuick
import Quickshell
import Quickshell.Io
import "../state" as AppState

// Thin client for the `pokitd` daemon. Owns the socket, parses events,
// exposes the same property surface that PokitProPopup.qml / PokitPro.qml
// were built against so no popup/bar-item changes are needed.
Item {
    id: root
    visible: false

    // ─── Public state (surface preserved for popup + bar item + IPC) ──────

    property string state: "absent"  // absent, connecting, active, error, paused
    property string deviceName: ""
    property string deviceMac: ""
    property int batteryLevel: -1   // percent derived from battery voltage
    property real batteryVoltage: 0
    property string firmware: ""
    property int signalDbm: 0
    property string lastError: ""

    // Activity (what's happening right now — see popup)
    property string activity: "idle"
    property string activityCmd: ""
    property double activityStartedAt: 0

    // Pause: by default we don't stream readings. User explicitly resumes.
    property bool paused: true

    // Current measurement (mirrored into same properties the popup already uses)
    property real readingValue: 0
    property string readingUnit: ""
    property string readingMode: ""
    property string readingRange: ""
    property string readingStatus: ""
    property double readingTimestamp: 0

    // Rolling history of recent readings for the Measure-tab trend chart.
    // Array of { t: epochMs, v: number }. Bounded to last ~60 seconds; cleared
    // on unit change (e.g. mode switch V → Ω) so we don't mix scales.
    property var readingHistory: []
    property string _histUnit: ""

    // User-facing mode/range names (display strings, same as before). The
    // widget translates to QtPokit enum names before sending to the daemon.
    property string currentMode: "DC Voltage"
    property string currentRange: "auto"

    // Logger
    property bool loggerRunning: false
    property var loggerSamples: []
    property string _loggerMetaMode: ""
    property string _loggerMetaUnit: ""
    property int _loggerMetaIntervalMs: 1000
    property double _loggerStartTs: 0

    // DSO (oscilloscope) — last completed trace
    property var dsoTrace: []        // QList of doubles in physical units
    property string dsoMode: ""
    property string dsoUnit: ""
    property real dsoSampleRateHz: 0
    property double dsoTimestamp: 0
    property int dsoProgress: 0      // collected so far (0 → expected)
    property int dsoExpected: 0
    property bool dsoCapturing: false

    // Legacy fields kept for popup bindings. Daemon owns retry now.
    property string busyOp: ""
    property int errorAttempt: 0
    property int errorBackoffMs: 0

    // Daemon link status
    property bool daemonConnected: sock.connected
    property string socketPath: ""

    property bool popupShouldShow: {
        if (AppState.ShellState.pokitPopupPinned) return true;
        if (AppState.ShellState.pokitPopupDismissed) return false;
        return state === "connecting" || state === "active" || state === "error";
    }

    // ─── Activity helper ─────────────────────────────────────────────────

    function _setActivity(text, argv) {
        activity = text;
        activityCmd = argv ? (typeof argv === "string" ? argv : argv.join(" ")) : "";
        activityStartedAt = Date.now();
    }

    // ─── Mode translation table ──────────────────────────────────────────
    // Display strings (preserved from the CLI-era UI) ↔ daemon wire names.

    readonly property var _displayToWire: ({
        "DC Voltage":  "DcVoltage",
        "AC Voltage":  "AcVoltage",
        "DC Current":  "DcCurrent",
        "AC Current":  "AcCurrent",
        "Resistance":  "Resistance",
        "Diode":       "Diode",
        "Continuity":  "Continuity",
        "Temperature": "Temperature",
        "Capacitance": "Capacitance"
    })
    readonly property var _wireToDisplay: ({
        "DcVoltage":   "DC Voltage",
        "AcVoltage":   "AC Voltage",
        "DcCurrent":   "DC Current",
        "AcCurrent":   "AC Current",
        "Resistance":  "Resistance",
        "Diode":       "Diode",
        "Continuity":  "Continuity",
        "Temperature": "Temperature",
        "Capacitance": "Capacitance"
    })

    function _toWireMode(display) {
        return root._displayToWire[display] || display;
    }
    function _fromWireMode(wire) {
        return root._wireToDisplay[wire] || wire;
    }

    // ─── Socket + reconnect ──────────────────────────────────────────────

    Socket {
        id: sock
        parser: SplitParser {
            splitMarker: "\n"
            onRead: data => root._handleEvent(data)
        }
        onConnectionStateChanged: {
            if (connected) {
                root.lastError = "";
                root._setActivity("connected to pokitd", null);
                // On connect, ask for a fresh scan so the daemon kicks off
                // its scan→connect flow if it was idle. Subscribe too
                // unless paused.
                root._send({type: "scan"});
                if (!root.paused) root._send({type: "subscribe"});
            } else {
                root._setActivity("pokitd offline — reconnecting…", null);
                root.state = "absent";
                root.readingTimestamp = 0;
                reconnectTimer.restart();
            }
        }
        onError: err => {
            root.lastError = "socket error: " + err;
        }
    }

    Timer {
        id: reconnectTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (!sock.connected && root.socketPath) sock.connected = true;
        }
    }

    property int _opCounter: 0
    function _nextOpId() { return "op-" + (++_opCounter); }

    function _send(msg) {
        if (!sock.connected) {
            root.lastError = "daemon not connected";
            return "";
        }
        if (!msg.opId) msg.opId = _nextOpId();
        sock.write(JSON.stringify(msg) + "\n");
        return msg.opId;
    }

    // ─── Event dispatcher ────────────────────────────────────────────────

    function _handleEvent(line) {
        if (!line) return;
        let ev;
        try { ev = JSON.parse(line); } catch (e) {
            root.lastError = "parse: " + e;
            return;
        }
        switch (ev.type) {
        case "hello":              _applyHello(ev); break;
        case "deviceState":        _applyDeviceState(ev); break;
        case "scanResult":         break;  // informational; deviceDiscovered already fires
        case "deviceDiscovered":   _applyDeviceDiscovered(ev); break;
        case "deviceConnected":    _applyDeviceConnected(ev); break;
        case "deviceDisconnected": _applyDeviceDisconnected(ev); break;
        case "status":             _applyStatus(ev); break;
        case "reading":            _applyReading(ev); break;
        case "settings":           _applySettings(ev); break;
        case "loggerState":        root.loggerRunning = !!ev.running; break;
        case "loggerMetadata":     _applyLoggerMetadata(ev); break;
        case "loggerBatch":        _applyLoggerBatch(ev); break;
        case "dsoProgress":        _applyDsoProgress(ev); break;
        case "dsoTrace":           _applyDsoTrace(ev); break;
        case "ack":                break;  // opId correlation is soft for now
        case "error":              _applyError(ev); break;
        case "pong":               break;
        }
    }

    function _applyLoggerMetadata(ev) {
        // Track whether device is still sampling.
        root.loggerRunning = (ev.status === "Sampling");
        // Stash mode/unit/intervalMs for subsequent batch display.
        root._loggerMetaMode = ev.mode || "";
        root._loggerMetaUnit = ev.unit || "";
        root._loggerMetaIntervalMs = ev.intervalMs || 1000;
        root._loggerStartTs = (ev.startTimestamp || 0) * 1000;  // secs → ms
        // Reset buffer when a fresh fetch begins.
        root.loggerSamples = [];
    }

    function _applyDsoProgress(ev) {
        root.dsoProgress = ev.collected || 0;
        root.dsoExpected = ev.total || 0;
        root.dsoCapturing = root.dsoProgress < root.dsoExpected;
    }

    function _applyDsoTrace(ev) {
        if (!Array.isArray(ev.values)) return;
        root.dsoTrace = ev.values;
        root.dsoMode = ev.mode || "";
        root.dsoUnit = ev.unit || "";
        root.dsoSampleRateHz = ev.samplingRate || 0;
        root.dsoTimestamp = Date.now();
        root.dsoCapturing = false;
        root.dsoProgress = ev.values.length;
        root.dsoExpected = ev.values.length;
    }

    function _applyLoggerBatch(ev) {
        if (!Array.isArray(ev.values)) return;
        const unit = ev.unit || root._loggerMetaUnit || "";
        const interval = ev.intervalMs || root._loggerMetaIntervalMs || 1000;
        let ts = root._loggerStartTs + root.loggerSamples.length * interval;
        const addition = ev.values.map(v => ({
            timestamp: (ts += interval) - interval,
            value: v,
            unit: unit
        }));
        // Keep up to 1000 samples in-memory to avoid unbounded growth.
        const combined = root.loggerSamples.concat(addition);
        root.loggerSamples = combined.slice(Math.max(0, combined.length - 1000));
    }

    function _applyHello(ev) {
        if (ev.deviceState) root.state = _mapDaemonState(ev.deviceState);
        if (ev.device && typeof ev.device === "object") {
            root.deviceName = ev.device.name || root.deviceName;
            root.deviceMac = ev.device.mac || root.deviceMac;
            if (typeof ev.device.rssi === "number") root.signalDbm = ev.device.rssi;
        }
        if (ev.reading && typeof ev.reading === "object") _applyReading(ev.reading);
        if (ev.settings && typeof ev.settings === "object") _applySettings(ev.settings);
        _setActivity("hello from pokitd", null);
    }

    function _mapDaemonState(s) {
        if (s === "idle" || s === "scanning") return "absent";
        if (s === "discovered" || s === "connecting" || s === "discoveringServices")
            return "connecting";
        if (s === "ready") return "active";
        if (s === "error" || s === "disconnecting") return s === "error" ? "error" : "absent";
        return "absent";
    }

    function _applyDeviceState(ev) {
        root.state = _mapDaemonState(ev.state);
        if (ev.state === "scanning")            _setActivity("scanning for Pokit devices", "dokit scan");
        else if (ev.state === "connecting")     _setActivity("connecting BLE", null);
        else if (ev.state === "discoveringServices") _setActivity("discovering GATT services", null);
        else if (ev.state === "ready")          _setActivity("ready" + (root.paused ? " (paused)" : ""), null);
        else if (ev.state === "idle")           _setActivity("idle", null);
    }

    function _applyDeviceDiscovered(ev) {
        root.deviceMac = ev.mac || root.deviceMac;
        root.deviceName = ev.name || root.deviceName;
        if (typeof ev.rssi === "number") root.signalDbm = ev.rssi;
    }

    function _applyDeviceConnected(ev) {
        root.deviceMac = ev.mac || root.deviceMac;
        root.deviceName = ev.name || root.deviceName;
        _setActivity("connected", null);
    }

    function _applyDeviceDisconnected(ev) {
        root.readingTimestamp = 0;
        root.batteryLevel = -1;
        root.firmware = "";
        _setActivity("disconnected: " + (ev.reason || ""), null);
    }

    function _applyStatus(ev) {
        if (typeof ev.batteryVoltage === "number") {
            root.batteryVoltage = ev.batteryVoltage;
            if (ev.batteryVoltage >= 2.0) {
                // Rough mapping for Pokit Pro Li-ion (3.0–4.2V).
                const v = ev.batteryVoltage;
                root.batteryLevel = Math.max(0, Math.min(100,
                    Math.round((v - 3.0) / 1.2 * 100)));
            }
        }
        if (ev.firmware) root.firmware = ev.firmware;
        if (ev.name) root.deviceName = ev.name;
    }

    function _applySettings(ev) {
        if (ev.mode) root.currentMode = _fromWireMode(ev.mode);
        if (ev.range) root.currentRange = ev.range;
    }

    function _applyReading(ev) {
        if (typeof ev.value !== "number") return;
        root.readingValue = ev.value;
        root.readingUnit = ev.unit || "";
        root.readingMode = ev.mode ? _fromWireMode(ev.mode) : "";
        root.readingRange = ev.range || "";
        root.readingStatus = ev.status || "";
        const now = Date.now();
        root.readingTimestamp = now;
        _pushReadingHistory(ev.value, now);
        // Readings imply the device is live, regardless of whatever
        // deviceState we last saw — useful when the daemon's scan/connect
        // events happened before we connected to the socket.
        if (root.state !== "active") root.state = "active";
        if (root.activity.indexOf("ready") === 0
            || root.activity === "connected"
            || root.activity.indexOf("resuming") === 0) {
            _setActivity("live: " + root.readingMode + " " + root.readingRange, null);
        }
    }

    function _pushReadingHistory(v, tsMs) {
        let arr = root.readingHistory || [];
        // On unit change (mode switch), discard history so Volts and Ohms
        // don't share a y-axis.
        if (root._histUnit !== "" && root._histUnit !== root.readingUnit) arr = [];
        root._histUnit = root.readingUnit;
        const cutoff = tsMs - 60 * 1000;
        const filtered = arr.filter(p => p.t >= cutoff);
        filtered.push({ t: tsMs, v: v });
        root.readingHistory = filtered;
    }

    function _applyError(ev) {
        root.lastError = (ev.code || "error") + ": " + (ev.message || "");
    }

    // ─── Public API (unchanged surface for popup/bar/IPC) ─────────────────

    function setMode(displayMode) {
        if (!displayMode || displayMode === currentMode) return;
        currentMode = displayMode;
        currentRange = "auto";
        _send({type: "setMode", mode: _toWireMode(displayMode), range: "auto"});
    }
    function setRange(r) {
        if (!r || r === currentRange) return;
        currentRange = r;
        _send({type: "setRange", range: r});
    }
    function setTorch(on) { _send({type: "setTorch", on: !!on}); }
    function flashLed()    { _send({type: "flashLed"}); }
    function rename(n)     { if (n) _send({type: "rename", name: n}); }
    function startLogger() {
        _send({type: "loggerStart", mode: _toWireMode(currentMode),
               range: currentRange, intervalMs: 1000});
        loggerRunning = true;
    }
    function stopLogger()  { _send({type: "loggerStop"}); loggerRunning = false; }
    function fetchLogger() { _send({type: "loggerFetch"}); }

    // DSO capture: mode is display string (e.g. "DC Voltage"); rate Hz; samples count.
    function captureDso(displayMode, sampleRateHz, samples) {
        const mode = _toWireMode(displayMode || currentMode);
        root.dsoCapturing = true;
        root.dsoProgress = 0;
        root.dsoExpected = samples || 1024;
        _send({
            type: "dsoCapture",
            mode: mode,
            sampleRateHz: sampleRateHz || 1000,
            samples: samples || 1024
        });
    }

    // Convenience: pick a target window duration (ms) and compute rate for
    // a fixed 1024-sample capture. Daemon may finish a capture already in
    // flight — cancelDso() only clears local state.
    function captureDsoByWindow(displayMode, windowMs) {
        const map = { 100: 10000, 500: 2000, 1000: 1000, 5000: 200, 10000: 100 };
        const rate = map[windowMs] || 1000;
        captureDso(displayMode, rate, 1024);
    }

    function cancelDso() {
        dsoTrace = [];
        dsoCapturing = false;
        dsoProgress = 0;
        dsoExpected = 0;
    }

    // Halts everything the widget is doing: pauses the reading stream, stops
    // the logger if running, and clears DSO state.
    function panicStop() {
        setPaused(true);
        if (loggerRunning) stopLogger();
        cancelDso();
    }

    function retry()       { _send({type: "connect"}); }
    function disconnect()  {
        _send({type: "disconnect"});
        _setActivity("disconnecting BLE", null);
    }
    function connect() {
        _send({type: "scan"});
        _setActivity("scanning to reconnect", null);
    }
    function dismiss()     { AppState.ShellState.pokitPopupDismissed = true; }

    function setPaused(p) {
        if (p === paused) return;
        paused = p;
        _send({type: paused ? "unsubscribe" : "subscribe"});
        _setActivity(paused ? "paused (BLE link kept)" : "resuming stream", null);
    }
    function togglePause() { setPaused(!paused); }

    // ─── Init ─────────────────────────────────────────────────────────────

    Component.onCompleted: {
        const rt = Quickshell.env("XDG_RUNTIME_DIR");
        const base = (rt && rt !== "") ? rt : "/tmp";
        root.socketPath = base + "/pokitd/sock";
        sock.path = root.socketPath;
        sock.connected = true;
    }

    // ─── ShellState IPC bridge (unchanged contract) ───────────────────────

    Connections {
        target: AppState.ShellState
        function onPokitDesiredModeChanged() {
            if (AppState.ShellState.pokitDesiredMode)
                root.setMode(AppState.ShellState.pokitDesiredMode);
        }
        function onPokitDesiredRangeChanged() {
            if (AppState.ShellState.pokitDesiredRange)
                root.setRange(AppState.ShellState.pokitDesiredRange);
        }
        function onPokitTorchRequestChanged() {
            const v = AppState.ShellState.pokitTorchRequest;
            if (v.indexOf("on:") === 0) root.setTorch(true);
            else if (v.indexOf("off:") === 0) root.setTorch(false);
        }
        function onPokitFlashRequestChanged() {
            if (AppState.ShellState.pokitFlashRequest) root.flashLed();
        }
        function onPokitRenameRequestChanged() {
            if (AppState.ShellState.pokitRenameRequest)
                root.rename(AppState.ShellState.pokitRenameRequest);
        }
        function onPokitLoggerCommandChanged() {
            const cmd = AppState.ShellState.pokitLoggerCommand;
            if (cmd.indexOf("start:") === 0) root.startLogger();
            else if (cmd.indexOf("stop:") === 0) root.stopLogger();
            else if (cmd.indexOf("fetch:") === 0) root.fetchLogger();
        }
        function onPokitPauseRequestChanged() {
            const v = AppState.ShellState.pokitPauseRequest;
            if (v.indexOf("pause:") === 0) root.setPaused(true);
            else if (v.indexOf("resume:") === 0) root.setPaused(false);
            else if (v.indexOf("toggle:") === 0) root.togglePause();
        }
        function onPokitDsoRequestChanged() {
            const v = AppState.ShellState.pokitDsoRequest;
            if (!v) return;
            const parts = v.split("|");
            if (parts.length < 4) return;
            root.captureDso(parts[0], parseInt(parts[1]), parseInt(parts[2]));
        }
    }

    // ─── Debug IPC (surface unchanged; daemon block added) ────────────────

    IpcHandler {
        target: "pokitDebug"

        function status(): string {
            const now = Date.now();
            const obj = {
                state: root.state,
                paused: root.paused,
                daemon: {
                    connected: root.daemonConnected,
                    socketPath: root.socketPath
                },
                popupShouldShow: root.popupShouldShow,
                popupPinned: AppState.ShellState.pokitPopupPinned,
                popupDismissed: AppState.ShellState.pokitPopupDismissed,
                device: {
                    name: root.deviceName,
                    mac: root.deviceMac,
                    battery: root.batteryLevel,
                    batteryVoltage: root.batteryVoltage,
                    firmware: root.firmware,
                    rssi: root.signalDbm
                },
                reading: {
                    value: root.readingValue,
                    unit: root.readingUnit,
                    mode: root.readingMode,
                    range: root.readingRange,
                    status: root.readingStatus,
                    timestamp: root.readingTimestamp,
                    ageMs: root.readingTimestamp > 0 ? now - root.readingTimestamp : null
                },
                current: { mode: root.currentMode, range: root.currentRange },
                logger: { running: root.loggerRunning,
                          samples: root.loggerSamples ? root.loggerSamples.length : 0 },
                activity: {
                    description: root.activity,
                    command: root.activityCmd,
                    startedAt: root.activityStartedAt,
                    elapsedMs: root.activityStartedAt > 0
                               ? now - root.activityStartedAt : 0
                },
                error: { lastError: root.lastError }
            };
            return JSON.stringify(obj, null, 2);
        }

        function state(): string { return root.state; }
        function reading(): string {
            if (root.readingTimestamp === 0) return "(no reading)";
            return root.readingValue + " " + root.readingUnit + " (" + root.readingMode + ")";
        }
        function activity(): string {
            const elapsed = root.activityStartedAt > 0
                ? ((Date.now() - root.activityStartedAt) / 1000).toFixed(1) + "s"
                : "";
            return root.activity + (elapsed ? "  ·  " + elapsed : "")
                + (root.activityCmd ? "\n  $ " + root.activityCmd : "");
        }
    }
}
