import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
Item {
    id: root
    property bool popupOpen: false

    implicitWidth: 1100
    implicitHeight: 920

    // ─── State, populated by qs-net-status loop ───────────────────────────
    property var wifi: null         // see qs-net-status JSON shape
    property var ethernet: null
    property var tailscale: ({ installed: false })
    // Filtered health: drop the redundant "Tailscale is stopped." entry,
    // which tailscaled keeps emitting even after the daemon has stopped.
    readonly property var activeHealth: {
        var h = (tailscale && tailscale.health) || [];
        var out = [];
        for (var i = 0; i < h.length; i++) {
            if (typeof h[i] === "string" && /tailscale is stopped/i.test(h[i])) continue;
            out.push(h[i]);
        }
        return out;
    }
    property var gatewayInfo: ({ gateway: "", dev: "", src: "" })
    property var dnsServers: []
    property bool _dnsTestPending: false
    onDnsServersChanged: {
        if (_dnsTestPending && dnsServers.length > 0) {
            _dnsTestPending = false;
            refreshDnsTest();
        }
    }

    property string gatewayIp: gatewayInfo.gateway || ""

    // ─── ipinfo (public IP) cache ─────────────────────────────────────────
    property var ipinfo: null
    property bool ipinfoLoading: false

    // ─── DNS self-test cache ──────────────────────────────────────────────
    // {system: {server, tests}, upstream: {server, tests}, external: {…}}
    property var dnsMethods: ({})
    property bool dnsTestLoading: false

    // ─── WiFi/Tailscale controls ──────────────────────────────────────────
    property bool wifiEnabled: true
    property var trafficHistory: []
    readonly property int trafficMaxHistory: 300
    property var wifiNetworks: []
    property int wifiNetworkCount: 0
    property bool wifiScanLoading: false
    property bool wifiConnecting: false
    property string wifiConnectError: ""
    property string passwordInputBssid: ""

    // ─── Bluetooth ─────────────────────────────────────────────────────────
    property var btController: null
    property var btDevices: []
    property bool btLoading: false
    property bool btScanLoading: false
    property bool btActionLoading: false
    property string btActionError: ""

    // ─── Ping series ──────────────────────────────────────────────────────
    readonly property int pingMaxHistory: 80
    property var pingTargets: [
        { id: "gw",  label: "Gateway",  iconCode: 0xF08F2, host: gatewayIp },
        { id: "ext", label: "1.1.1.1",  iconCode: 0xF059F, host: "1.1.1.1" },
        { id: "dns", label: "8.8.8.8",  iconCode: 0xF059F, host: "8.8.8.8" }
    ]

    onPopupOpenChanged: {
        if (popupOpen) {
            statusLoop.running = true;
            refreshIpInfo();
            if (root.dnsServers.length > 0)
                refreshDnsTest();
            else
                root._dnsTestPending = true;
            loadWifiNetworks();
            loadBtStatus();
        } else {
            statusLoop.running = false;
            root.trafficHistory = [];
            root.passwordInputBssid = "";
            root.wifiConnectError = "";
            root.btActionError = "";
        }
    }

    function refreshDnsTest() {
        if (root.dnsTestLoading) return;
        root.dnsTestLoading = true;
        var upstream = (root.dnsServers && root.dnsServers.length > 0)
            ? root.dnsServers[0] : "";
        var url = upstream
            ? "http://d/dns/test?upstream=" + encodeURIComponent(upstream)
            : "http://d/dns/test";
        dnsTestProc.command = ["curl", "-s", "--unix-socket", root._sock, url];
        dnsTestProc.running = true;
    }

    function loadWifiNetworks() {
        if (root.wifiScanLoading) return;
        root.wifiScanLoading = true;
        wifiCachedProc.running = true;
    }

    function scanWifiNetworks() {
        if (root.wifiScanLoading) return;
        root.wifiScanLoading = true;
        wifiScanProc.running = true;
    }

    function connectToWifi(ssid, bssid, password, known) {
        root.wifiConnecting = true;
        root.wifiConnectError = "";
        var body = {ssid: ssid};
        if (bssid) body.bssid = bssid;
        if (password) body.password = password;
        if (known) body.known = true;
        wifiConnectProc.command = ["curl", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify(body),
            "--unix-socket", root._sock, "http://d/net/wifi-connect"];
        wifiConnectProc.running = true;
    }

    // ─── Bluetooth functions ────────────────────────────────────────────
    function loadBtStatus() {
        if (root.btLoading) return;
        root.btLoading = true;
        btStatusProc.running = true;
    }

    function scanBtDevices() {
        if (root.btScanLoading) return;
        root.btScanLoading = true;
        btScanProc.running = true;
    }

    function btConnect(mac) {
        root.btActionLoading = true;
        root.btActionError = "";
        btActionProc.command = ["curl", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({mac: mac}),
            "--unix-socket", root._sock, "http://d/bt/connect"];
        btActionProc.running = true;
    }

    function btDisconnect(mac) {
        root.btActionLoading = true;
        root.btActionError = "";
        btActionProc.command = ["curl", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({mac: mac}),
            "--unix-socket", root._sock, "http://d/bt/disconnect"];
        btActionProc.running = true;
    }

    function btRemove(mac) {
        root.btActionLoading = true;
        root.btActionError = "";
        btActionProc.command = ["curl", "-s", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({mac: mac}),
            "--unix-socket", root._sock, "http://d/bt/remove"];
        btActionProc.running = true;
    }

    function btIconForType(icon) {
        if (icon === "audio-headset" || icon === "audio-headphones") return String.fromCodePoint(0xF07CE);
        if (icon === "audio-card") return String.fromCodePoint(0xF075A);
        if (icon === "input-keyboard") return String.fromCodePoint(0xF030C);
        if (icon === "input-mouse") return String.fromCodePoint(0xF037D);
        if (icon === "input-gaming") return String.fromCodePoint(0xF0EB5);
        if (icon === "phone") return String.fromCodePoint(0xF03F2);
        if (icon === "computer") return String.fromCodePoint(0xF0379);
        if (icon === "video-display") return String.fromCodePoint(0xF0379);
        return String.fromCodePoint(0xF00AF);
    }

    function fmtRate(bytesPerSec) {
        if (!bytesPerSec || bytesPerSec < 1024) return (Math.round(bytesPerSec) || 0) + " B/s";
        if (bytesPerSec < 1048576) return (bytesPerSec / 1024).toFixed(1) + " KB/s";
        if (bytesPerSec < 1073741824) return (bytesPerSec / 1048576).toFixed(1) + " MB/s";
        return (bytesPerSec / 1073741824).toFixed(1) + " GB/s";
    }

    function signalIconForPct(signal) {
        if (signal >= 75) return String.fromCodePoint(0xF0928);
        if (signal >= 50) return String.fromCodePoint(0xF0925);
        if (signal >= 25) return String.fromCodePoint(0xF0922);
        return String.fromCodePoint(0xF091F);
    }

    function signalColorForPct(signal) {
        if (signal >= 75) return "#4caf50";
        if (signal >= 50) return "#8bc34a";
        if (signal >= 25) return "#ffb74d";
        return "#ef5350";
    }

    // ─── Helpers ──────────────────────────────────────────────────────────
    function fmtBytes(b) {
        if (!b || b < 1024) return (b || 0) + " B";
        if (b < 1048576) return (b / 1024).toFixed(1) + " KB";
        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB";
        return (b / 1073741824).toFixed(1) + " GB";
    }

    function fmtBitrate(mbps) {
        if (!mbps) return "—";
        if (mbps >= 1000) return (mbps / 1000).toFixed(1) + " Gb/s";
        return Math.round(mbps) + " Mb/s";
    }

    function fmtSpeedMbps(s) {
        if (!s || s <= 0) return "—";
        if (s >= 1000) return (s / 1000).toFixed(1) + " Gb/s";
        return s + " Mb/s";
    }

    function fmtUptime(secs) {
        if (!secs) return "—";
        if (secs >= 86400) {
            var d = Math.floor(secs / 86400);
            var h = Math.floor((secs % 86400) / 3600);
            return d + "d " + h + "h";
        }
        if (secs >= 3600) {
            var hh = Math.floor(secs / 3600);
            var mm = Math.floor((secs % 3600) / 60);
            return hh + "h " + mm + "m";
        }
        if (secs >= 60) {
            var m = Math.floor(secs / 60);
            return m + "m " + (secs % 60) + "s";
        }
        return secs + "s";
    }

    function signalColor(dbm) {
        if (dbm === null || dbm === undefined) return Helpers.Colors.disconnected;
        if (dbm >= -50) return "#4caf50";
        if (dbm >= -60) return "#8bc34a";
        if (dbm >= -67) return "#ffb74d";
        if (dbm >= -75) return "#ef5350";
        return "#f44336";
    }

    function signalQuality(dbm) {
        if (dbm === null || dbm === undefined) return "—";
        if (dbm >= -50) return "Excellent";
        if (dbm >= -60) return "Good";
        if (dbm >= -67) return "Fair";
        if (dbm >= -75) return "Weak";
        return "Poor";
    }

    function genColor(g) {
        if (g === "7") return "#bb86fc";
        if (g === "6E") return "#4dd0e1";
        if (g === "6") return "#66bb6a";
        if (g === "5") return "#ffa726";
        if (g === "4") return "#ef5350";
        return Helpers.Colors.textMuted;
    }

    function genLabel(g) {
        if (g === "7") return "Wi-Fi 7";
        if (g === "6E") return "Wi-Fi 6E";
        if (g === "6") return "Wi-Fi 6";
        if (g === "5") return "Wi-Fi 5";
        if (g === "4") return "Wi-Fi 4";
        return "Legacy";
    }

    function bandColor(b) {
        if (!b) return Helpers.Colors.textMuted;
        if (b.indexOf("6") === 0) return "#bb86fc";
        if (b.indexOf("5") === 0) return "#42a5f5";
        return "#8d6e63";
    }

    function retriesText(retries, total) {
        if (!total) return "—";
        if (retries > total * 10) return "—";
        var pct = retries / total * 100;
        return pct.toFixed(1) + "%";
    }

    function retriesColor(retries, total) {
        if (!total || retries > total * 10) return Helpers.Colors.textMuted;
        var pct = retries / total * 100;
        if (pct < 5) return "#66bb6a";
        if (pct < 15) return "#ffb74d";
        return "#ef5350";
    }

    function refreshIpInfo() {
        if (root.ipinfoLoading) return;
        root.ipinfoLoading = true;
        ipinfoProc.running = true;
    }

    readonly property string _sock: AppConfig.Config.daemon.socket

    // ─── Long-lived status stream (NDJSON from daemon, 1s cadence) ───────
    Process {
        id: statusLoop
        command: ["curl", "-sN", "--unix-socket", root._sock, "http://d/net/stream"]
        running: false
        stdout: SplitParser {
            onRead: line => root.applyStatus(line)
        }
    }

    function applyStatus(raw) {
        if (!raw) return;
        try {
            var d = JSON.parse(raw.trim());
            if (d.gateway) root.gatewayInfo = d.gateway;
            if (d.dns) root.dnsServers = d.dns;
            root.wifi = d.wifi;
            root.ethernet = d.ethernet;
            root.tailscale = d.tailscale || { installed: false };
            if (d.wifi_enabled !== undefined) root.wifiEnabled = d.wifi_enabled;

            // Seed traffic history from daemon on first message
            if (d.traffic_history && d.traffic_history.length > 0 && root.trafficHistory.length === 0) {
                root.trafficHistory = d.traffic_history;
            } else {
                var rxRate = 0, txRate = 0;
                if (d.wifi && d.wifi.rx_rate) { rxRate += d.wifi.rx_rate; txRate += (d.wifi.tx_rate || 0); }
                if (d.ethernet && d.ethernet.rx_rate) { rxRate += d.ethernet.rx_rate; txRate += (d.ethernet.tx_rate || 0); }
                var h = root.trafficHistory.slice();
                h.push({ rx: rxRate, tx: txRate });
                if (h.length > root.trafficMaxHistory) h.shift();
                root.trafficHistory = h;
            }
            trafficGraph.requestPaint();
        } catch (e) {
            console.warn("network/Popup: status parse error", e, raw.substring(0, 120));
        }
    }

    // ─── ipinfo (public IP geo lookup) ────────────────────────────────────
    Process {
        id: ipinfoProc
        // ip-api.com free tier only serves HTTP — HTTPS requires a paid key.
        command: ["bash", "-c", "curl -sS --max-time 5 'http://ip-api.com/json/?fields=66846719' || echo '{}'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.ipinfoLoading = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    if (d && d.status === "success") root.ipinfo = d;
                } catch (e) { /* ignore */ }
            }
        }
    }

    // ─── DNS self-test (via daemon) ─────────────────────────────────────
    Process {
        id: dnsTestProc
        command: ["echo", "{}"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.dnsTestLoading = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    if (d && d.methods) root.dnsMethods = d.methods;
                } catch (e) { /* ignore */ }
            }
        }
    }

    // ─── WiFi/Tailscale control processes ────────────────────────────────
    Process {
        id: wifiToggleProc
        command: ["curl", "-s", "-X", "POST", "--unix-socket", root._sock, "http://d/net/wifi-toggle"]
        running: false
    }

    Process {
        id: tailscaleToggleProc
        command: ["curl", "-s", "-X", "POST", "--unix-socket", root._sock, "http://d/net/tailscale-toggle"]
        running: false
    }

    Process {
        id: wifiCachedProc
        command: ["curl", "-s", "--unix-socket", root._sock, "http://d/net/wifi-list"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanLoading = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    if (d.networks) {
                        root.wifiNetworks = d.networks;
                        root.wifiNetworkCount = d.count || 0;
                    }
                } catch (e) { /* ignore */ }
            }
        }
    }

    Process {
        id: wifiScanProc
        command: ["curl", "-s", "--unix-socket", root._sock, "http://d/net/wifi-scan"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiScanLoading = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    if (d.networks) {
                        root.wifiNetworks = d.networks;
                        root.wifiNetworkCount = d.count || 0;
                    }
                } catch (e) { /* ignore */ }
            }
        }
    }

    Process {
        id: wifiConnectProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.wifiConnecting = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    if (d.success) {
                        root.wifiConnectError = "";
                        root.passwordInputBssid = "";
                        root.scanWifiNetworks();
                    } else {
                        root.wifiConnectError = d.message || "Connection failed";
                    }
                } catch (e) {
                    root.wifiConnectError = "Connection failed";
                }
            }
        }
    }

    // ─── Bluetooth processes ────────────────────────────────────────────
    Process {
        id: btStatusProc
        command: ["curl", "-s", "--unix-socket", root._sock, "http://d/bt/status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.btLoading = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    root.btController = d.controller || null;
                    root.btDevices = d.devices || [];
                } catch (e) { /* ignore */ }
            }
        }
    }

    Process {
        id: btScanProc
        command: ["curl", "-s", "--unix-socket", root._sock, "http://d/bt/scan"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.btScanLoading = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    if (d.devices) root.btDevices = d.devices;
                } catch (e) { /* ignore */ }
                root.loadBtStatus();
            }
        }
    }

    Process {
        id: btActionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.btActionLoading = false;
                try {
                    var d = JSON.parse(this.text.trim() || "{}");
                    if (!d.success) root.btActionError = d.message || "Failed";
                } catch (e) {
                    root.btActionError = "Failed";
                }
                root.loadBtStatus();
            }
        }
    }

    Process {
        id: btTogglePowerProc
        command: ["curl", "-s", "-X", "POST", "--unix-socket", root._sock, "http://d/bt/toggle-power"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.loadBtStatus()
        }
    }

    Process {
        id: btToggleDiscoverableProc
        command: ["curl", "-s", "-X", "POST", "--unix-socket", root._sock, "http://d/bt/toggle-discoverable"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.loadBtStatus()
        }
    }

    Process {
        id: btToggleScanProc
        command: ["curl", "-s", "-X", "POST", "--unix-socket", root._sock, "http://d/bt/toggle-scan"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.loadBtStatus()
        }
    }

    Timer {
        id: btScanRefreshTimer
        interval: 3000
        running: root.popupOpen && root.btController && root.btController.discovering
        repeat: true
        onTriggered: root.loadBtStatus()
    }

    // ─── Layout ───────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent

        Item {
            id: surface
            anchors.fill: parent
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface { anchors.fill: parent }
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 14
            anchors.topMargin: 12
            contentHeight: mainColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

        Column {
            id: mainColumn
            width: parent.width
            spacing: 10

            // ── Header ───────────────────────────────────────────────────
            Row {
                width: parent.width
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF048D)   // network
                    color: Helpers.Colors.accent
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: 18
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Network"
                    color: Helpers.Colors.textDefault
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                    font.bold: true
                }

                Item { width: 1; height: 1 }   // flex spacer fallback
            }

            // ── Ping section ─────────────────────────────────────────────
            Row {
                width: parent.width
                spacing: 10

                Repeater {
                    model: root.pingTargets
                    delegate: PingPanel {
                        required property var modelData
                        target: modelData
                        width: (parent.width - 20) / 3
                        height: 150
                    }
                }
            }

            // ── Wi-Fi / Ethernet / Tailscale row ─────────────────────────
            Row {
                width: parent.width
                spacing: 10
                height: 260

                // Wi-Fi card
                Rectangle {
                    width: (parent.width - 20) / 3
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.04)
                    radius: 8

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Row {
                            spacing: 8
                            Text {
                                text: String.fromCodePoint(root.wifi && root.wifi.connected ? 0xF05A9 : 0xF05AA)
                                color: root.wifi && root.wifi.connected ? root.signalColor(root.wifi.signal_dbm) : Helpers.Colors.disconnected
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Wi-Fi"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.wifi && root.wifi.iface ? root.wifi.iface : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07); visible: true }

                        // Disconnected state
                        Text {
                            visible: !(root.wifi && root.wifi.connected)
                            text: root.wifi && root.wifi.iface ? "Not connected" : "No wireless interface"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                        }

                        // Connected — primary fields
                        Column {
                            visible: root.wifi && root.wifi.connected
                            spacing: 3
                            width: parent.width

                            InfoLine {
                                iconCode: 0xF048D                          // 󰒍 network
                                label: "SSID"
                                value: root.wifi ? (root.wifi.ssid || "—") : "—"
                                valueBold: true
                            }
                            InfoLine {
                                iconCode: 0xF0A0B                          // 󰨋 access-point
                                label: "BSSID"
                                value: root.wifi ? (root.wifi.bssid || "—") : "—"
                                valueMono: true
                            }
                            InfoLine {
                                iconCode: 0xF0A5F                          // 󰩟 ip-network
                                label: "IP"
                                value: root.wifi ? (root.wifi.ip || "—") : "—"
                                valueMono: true
                            }
                            InfoLine {
                                iconCode: 0xF05A9                          // 󰖩 wifi (band)
                                iconColor: root.bandColor(root.wifi ? root.wifi.band : "")
                                label: "Band"
                                value: root.wifi ? (root.wifi.band || "—") : "—"
                                valueColor: root.bandColor(root.wifi ? root.wifi.band : "")
                                valueBold: true
                                valueExtra: {
                                    var parts = [];
                                    if (root.wifi && root.wifi.channel) parts.push("ch " + root.wifi.channel);
                                    if (root.wifi && root.wifi.width) parts.push(root.wifi.width);
                                    if (root.wifi && root.wifi.mlo) parts.push("MLO");
                                    return parts.join("  ");
                                }
                            }
                            InfoLine {
                                iconCode: 0xF04C5                          // 󰓅 speedometer
                                label: "Gen"
                                value: root.genLabel(root.wifi ? root.wifi.gen : "")
                                valueColor: root.genColor(root.wifi ? root.wifi.gen : "")
                                valueBold: true
                            }
                            InfoLine {
                                iconCode: 0xF091F                          // 󰤟 wifi-strength-1 (signal)
                                iconColor: root.signalColor(root.wifi ? root.wifi.signal_dbm : null)
                                label: "Signal"
                                value: root.wifi && root.wifi.signal_dbm !== null && root.wifi.signal_dbm !== undefined
                                    ? root.wifi.signal_dbm + " dBm" : "—"
                                valueColor: root.signalColor(root.wifi ? root.wifi.signal_dbm : null)
                                valueBold: true
                                valueExtra: root.signalQuality(root.wifi ? root.wifi.signal_dbm : null)
                            }
                            // Signal bar (aligned to start under the value column at x=86)
                            Item {
                                width: parent.width
                                height: 5
                                visible: root.wifi && root.wifi.connected && root.wifi.signal_dbm !== null
                                Rectangle {
                                    x: 86
                                    width: parent.width - 86
                                    height: 4
                                    color: Qt.rgba(1, 1, 1, 0.08)
                                    radius: 2

                                    Rectangle {
                                        height: parent.height
                                        radius: 2
                                        color: root.signalColor(root.wifi ? root.wifi.signal_dbm : -100)
                                        width: {
                                            var d = root.wifi ? root.wifi.signal_dbm : -100;
                                            if (d === null || d === undefined) return 0;
                                            if (d > -40) d = -40;
                                            if (d < -80) d = -80;
                                            return parent.width * ((d + 80) / 40);
                                        }
                                        Behavior on width { NumberAnimation { duration: 250 } }
                                    }
                                }
                            }
                            InfoLine {
                                iconCode: 0xF04E1                          // 󰓡 swap-vertical
                                label: "Rate"
                                value: "↑ " + root.fmtBitrate(root.wifi ? root.wifi.tx_mbps : 0)
                                valueColor: "#64b5f6"
                                valueBold: true
                                valueExtra: "↓ " + root.fmtBitrate(root.wifi ? root.wifi.rx_mbps : 0)
                                valueExtraColor: "#42a5f5"
                            }
                            InfoLine {
                                iconCode: 0xF0453                          // 󰑓 refresh
                                label: "Retries"
                                value: root.wifi ? root.retriesText(root.wifi.tx_retries, root.wifi.tx_packets) : "—"
                                valueColor: root.wifi ? root.retriesColor(root.wifi.tx_retries, root.wifi.tx_packets) : Helpers.Colors.textMuted
                                valueExtra: root.wifi && root.wifi.beacon_loss > 0
                                    ? String.fromCodePoint(0xF0029) + " " + root.wifi.beacon_loss + " beacons" : ""
                                valueExtraColor: "#ef5350"
                            }
                            InfoLine {
                                iconCode: 0xF0954                          // 󰥔 clock-outline
                                label: "Uptime"
                                value: root.fmtUptime(root.wifi ? root.wifi.connected_time : 0)
                            }
                            InfoLine {
                                iconCode: 0xF04E6                          // 󰓦 swap-horizontal
                                label: "Traffic"
                                value: "↑ " + root.fmtBytes(root.wifi ? root.wifi.tx_bytes : 0)
                                valueColor: "#64b5f6"
                                valueExtra: "↓ " + root.fmtBytes(root.wifi ? root.wifi.rx_bytes : 0)
                                valueExtraColor: "#42a5f5"
                            }
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 10
                        anchors.rightMargin: 10
                        width: 34; height: 16; radius: 8
                        color: root.wifiEnabled ? "#4caf50" : Qt.rgba(1, 1, 1, 0.15)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.wifiEnabled ? parent.width - width - 2 : 2
                            color: "#ffffff"
                            Behavior on x { NumberAnimation { duration: 200 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wifiToggleProc.running = true
                        }
                    }
                }

                // Ethernet card
                Rectangle {
                    width: (parent.width - 20) / 3
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.04)
                    radius: 8

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Row {
                            spacing: 8
                            Text {
                                text: String.fromCodePoint(0xF0200)   // ethernet
                                color: root.ethernet && root.ethernet.connected ? "#90caf9" : Helpers.Colors.disconnected
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Ethernet"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.ethernet && root.ethernet.iface ? root.ethernet.iface : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

                        Text {
                            visible: !(root.ethernet && root.ethernet.iface)
                            text: "No ethernet interface"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                        }

                        Column {
                            visible: root.ethernet && root.ethernet.iface
                            spacing: 3
                            width: parent.width

                            InfoLine {
                                iconCode: 0xF06A5                          // 󰚥 lan / plug
                                iconColor: root.ethernet && root.ethernet.connected ? "#66bb6a" : "#ef5350"
                                label: "Link"
                                value: root.ethernet && root.ethernet.connected ? "up" : (root.ethernet ? root.ethernet.operstate : "—")
                                valueColor: root.ethernet && root.ethernet.connected ? "#66bb6a" : "#ef5350"
                                valueBold: true
                            }
                            InfoLine {
                                iconCode: 0xF04C5                          // 󰓅 speedometer
                                label: "Speed"
                                value: root.fmtSpeedMbps(root.ethernet ? root.ethernet.speed_mbps : 0)
                                valueBold: true
                                valueExtra: root.ethernet && root.ethernet.duplex ? root.ethernet.duplex : ""
                            }
                            InfoLine {
                                iconCode: 0xF0A5F                          // 󰩟 ip-network
                                label: "IP"
                                value: root.ethernet ? (root.ethernet.ip || "—") : "—"
                                valueMono: true
                            }
                            InfoLine {
                                iconCode: 0xF061A                          // 󰘚 memory / chip
                                label: "MAC"
                                value: root.ethernet ? (root.ethernet.mac || "—") : "—"
                                valueMono: true
                            }
                            InfoLine {
                                iconCode: 0xF04E6                          // 󰓦 swap-horizontal
                                label: "Traffic"
                                value: "↑ " + root.fmtBytes(root.ethernet ? root.ethernet.tx_bytes : 0)
                                valueColor: "#64b5f6"
                                valueExtra: "↓ " + root.fmtBytes(root.ethernet ? root.ethernet.rx_bytes : 0)
                                valueExtraColor: "#42a5f5"
                            }
                        }

                        // Shared "Local network" subsection — visible whenever
                        // a default route exists, even on wifi-only hosts.
                        Column {
                            visible: !!root.gatewayInfo.gateway
                            width: parent.width
                            spacing: 3

                            Item { width: 1; height: 6 }

                            SubHeader {
                                iconCode: 0xF08F2                          // 󰣲 router-wireless
                                iconColor: "#90caf9"
                                label: "Local network"
                            }
                            InfoLine {
                                iconCode: 0xF08F0                          // 󰣰 router
                                label: "Gateway"
                                value: root.gatewayInfo.gateway || "—"
                                valueMono: true
                            }
                            InfoLine {
                                iconCode: 0xF0815                          // 󰠕 arrow-right-thick (via)
                                label: "Via"
                                value: root.gatewayInfo.dev || "—"
                                valueMono: true
                                valueExtra: root.gatewayInfo.src ? "(" + root.gatewayInfo.src + ")" : ""
                            }
                            InfoLine {
                                iconCode: 0xF0E5C                          // 󰹜 dns
                                label: "DNS"
                                value: root.dnsServers.length ? root.dnsServers.join("  ") : "—"
                                valueMono: true
                            }
                        }
                    }
                }

                // Tailscale card
                Rectangle {
                    width: (parent.width - 20) / 3
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.04)
                    radius: 8

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4

                        Row {
                            spacing: 8
                            Text {
                                text: String.fromCodePoint(0xF08C0)   // lan_connect
                                color: root.tailscale && root.tailscale.running ? "#4caf50"
                                     : (root.tailscale && root.tailscale.installed ? "#ffb74d" : Helpers.Colors.disconnected)
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Tailscale"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

                        Text {
                            visible: !(root.tailscale && root.tailscale.installed)
                            text: "Not installed"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                        }

                        Column {
                            visible: root.tailscale && root.tailscale.installed
                            spacing: 3
                            width: parent.width

                            InfoLine {
                                iconCode: 0xF012F                          // 󰄯 circle-medium (state dot)
                                iconColor: root.tailscale.running ? "#66bb6a"
                                    : (root.tailscale.state === "NeedsLogin" ? "#ffb74d" : "#ef5350")
                                label: "State"
                                value: root.tailscale.state || "—"
                                valueColor: root.tailscale.running ? "#66bb6a"
                                    : (root.tailscale.state === "NeedsLogin" ? "#ffb74d" : "#ef5350")
                                valueBold: true
                            }
                            InfoLine {
                                iconCode: 0xF0379                          // 󰍹 monitor / hostname
                                label: "Hostname"
                                value: root.tailscale.hostname || "—"
                            }
                            InfoLine {
                                iconCode: 0xF0E5C                          // 󰹜 dns
                                label: "DNS"
                                value: root.tailscale.dns_name || "—"
                                valueMono: true
                            }
                            InfoLine {
                                iconCode: 0xF0A5F                          // 󰩟 ip-network
                                label: "IPv4"
                                value: (root.tailscale.ips && root.tailscale.ips.length) ? root.tailscale.ips[0] : "—"
                                valueMono: true
                                valueBold: true
                            }
                            InfoLine {
                                iconCode: 0xF0A60                          // 󰩠 ip
                                label: "IPv6"
                                value: (root.tailscale.ips && root.tailscale.ips.length > 1) ? root.tailscale.ips[1] : "—"
                                valueMono: true
                            }
                            InfoLine {
                                iconCode: 0xF0343                          // 󰍃 logout / exit
                                label: "Exit"
                                value: root.tailscale.exit_node || "—"
                            }
                            InfoLine {
                                iconCode: 0xF0849                          // 󰡉 account-group
                                label: "Peers"
                                value: (root.tailscale.peer_online !== undefined)
                                    ? (root.tailscale.peer_online + " / " + root.tailscale.peer_total + " online")
                                    : "—"
                            }

                            // Health warnings — only meaningful while running
                            // (tailscaled keeps stale messages like the
                            // "Madrid relay" one across stop/start cycles).
                            Column {
                                visible: !!(root.tailscale.running && root.activeHealth.length > 0)
                                width: parent.width
                                spacing: 2
                                Item { width: 1; height: 4 }
                                Repeater {
                                    model: root.activeHealth
                                    Item {
                                        required property var modelData
                                        width: parent.width
                                        height: warnText.implicitHeight + 2
                                        Text {
                                            x: 0
                                            anchors.top: parent.top
                                            width: 14
                                            text: String.fromCodePoint(0xF0029) // 󰀩 alert
                                            color: "#ef5350"
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Text {
                                            id: warnText
                                            x: 18
                                            anchors.top: parent.top
                                            width: parent.width - 20
                                            text: modelData
                                            color: "#ef9a9a"
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 10
                        anchors.rightMargin: 10
                        width: 34; height: 16; radius: 8
                        visible: root.tailscale && root.tailscale.installed
                        color: root.tailscale && root.tailscale.running ? "#4caf50" : Qt.rgba(1, 1, 1, 0.15)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.tailscale && root.tailscale.running ? parent.width - width - 2 : 2
                            color: "#ffffff"
                            Behavior on x { NumberAnimation { duration: 200 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tailscaleToggleProc.running = true
                        }
                    }
                }
            }

            // ── WiFi Networks + Network Traffic (side by side) ─────────
            Row {
                width: parent.width
                spacing: 10
                height: 240

                // ── WiFi Networks (left, hidden when wifi off) ───────────
                Rectangle {
                    visible: root.wifiEnabled
                    width: visible ? (parent.width - 10) / 2 : 0
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.04)
                    radius: 8

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        Item {
                            width: parent.width
                            height: 20

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCodePoint(0xF05A9)
                                    color: "#90caf9"
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: 14
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Wi-Fi"
                                    color: Helpers.Colors.textDefault
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                    font.bold: true
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.wifiNetworkCount > 0
                                    width: countText.implicitWidth + 8
                                    height: 16; radius: 3
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                    Text {
                                        id: countText
                                        anchors.centerIn: parent
                                        text: root.wifiNetworkCount
                                        color: Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                        font.bold: true
                                    }
                                }
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                transformOrigin: Item.Center
                                text: String.fromCodePoint(0xF0453)
                                color: wifiScanRefreshMA.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                                opacity: root.wifiScanLoading ? 0.5 : 1.0
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 14
                                RotationAnimation on rotation {
                                    running: root.wifiScanLoading
                                    from: 0; to: 360; duration: 800
                                    loops: Animation.Infinite
                                }
                                MouseArea {
                                    id: wifiScanRefreshMA
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.wifiScanLoading
                                    onClicked: root.scanWifiNetworks()
                                }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

                        Text {
                            visible: root.wifiConnectError !== ""
                            text: String.fromCodePoint(0xF0029) + " " + root.wifiConnectError
                            color: "#ef5350"
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            width: parent.width
                            elide: Text.ElideRight
                        }

                        Flickable {
                            width: parent.width
                            height: parent.height - 30 - (root.wifiConnectError !== "" ? 16 : 0)
                            contentHeight: networkListCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: networkListCol
                                width: parent.width
                                spacing: 1

                                Text {
                                    visible: root.wifiNetworks.length === 0
                                    text: root.wifiScanLoading ? "Scanning…" : (root.wifiEnabled ? "No networks" : "Wi-Fi off")
                                    color: Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                }

                                Repeater {
                                    model: root.wifiNetworks
                                    delegate: Column {
                                        id: apDelegate
                                        required property var modelData
                                        required property int index
                                        width: parent.width
                                        spacing: 0

                                        // ── Group header (SSID label, not clickable) ──
                                        Item {
                                            visible: modelData.group_first
                                            width: parent.width
                                            height: visible ? 26 : 0

                                            // Gap before group (except first)
                                            Rectangle {
                                                visible: apDelegate.index > 0
                                                anchors.top: parent.top
                                                width: parent.width; height: 1
                                                color: Qt.rgba(1,1,1,0.08)
                                            }

                                            Row {
                                                anchors.left: parent.left; anchors.leftMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 4

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: String.fromCodePoint(0xF05A9)
                                                    color: Helpers.Colors.textMuted
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.ssid
                                                    color: Helpers.Colors.textDefault
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                    width: Math.min(implicitWidth, 140)
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: modelData.ssid_count > 1
                                                    text: modelData.ssid_count + " AP"
                                                    color: Helpers.Colors.textMuted
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.security || ""
                                                    color: {
                                                        var s = modelData.security || ""
                                                        if (s === "Open") return "#ef5350"
                                                        if (s === "WPA3" || s === "WPA2/3") return "#66bb6a"
                                                        return Helpers.Colors.textMuted
                                                    }
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                }
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: !!modelData.known
                                                    width: savedLabel.implicitWidth + 8
                                                    height: 14; radius: 3
                                                    color: Qt.rgba(0.30, 0.69, 0.31, 0.15)
                                                    border.color: "#66bb6a"; border.width: 1
                                                    Text {
                                                        id: savedLabel
                                                        anchors.centerIn: parent
                                                        text: "Saved"
                                                        color: "#66bb6a"
                                                        font.family: AppConfig.Config.theme.fontFamily
                                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                        font.bold: true
                                                    }
                                                }
                                            }
                                        }

                                        // ── AP row (clickable, shows BSSID) ──
                                        Rectangle {
                                            property bool isActive: !!modelData.active
                                            property bool isOpen: modelData.security === "Open" || modelData.security === ""
                                            width: parent.width
                                            height: 24
                                            radius: 2
                                            color: {
                                                if (isActive) return Qt.rgba(0.05, 0.68, 0.29, 0.12)
                                                if (isOpen) return Qt.rgba(0.96, 0.26, 0.21, 0.08)
                                                if (apMA.containsMouse) return Qt.rgba(1,1,1,0.08)
                                                return "transparent"
                                            }

                                            Rectangle {
                                                visible: parent.isOpen && !parent.isActive
                                                width: 2; radius: 1
                                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                                anchors.left: parent.left
                                                anchors.topMargin: 2; anchors.bottomMargin: 2
                                                color: "#ef5350"
                                            }

                                            Rectangle {
                                                visible: parent.isActive
                                                width: 2; radius: 1
                                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                                anchors.left: parent.left
                                                anchors.topMargin: 2; anchors.bottomMargin: 2
                                                color: "#66bb6a"
                                            }

                                            Row {
                                                anchors.left: parent.left
                                                anchors.right: apSignalText.left
                                                anchors.rightMargin: 2
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.leftMargin: 6
                                                spacing: 0

                                                Text { anchors.verticalCenter: parent.verticalCenter; width: 14; text: root.signalIconForPct(modelData.signal); color: root.signalColorForPct(modelData.signal); font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; horizontalAlignment: Text.AlignHCenter }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter; width: 120
                                                    text: modelData.bssid || ""
                                                    color: modelData.active ? "#66bb6a" : Helpers.Colors.textMuted
                                                    font.family: "DejaVuSansM Nerd Font Mono"
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter; width: 20
                                                    text: {
                                                        var g = modelData.gen || ""
                                                        if (g === "7") return "7"
                                                        if (g === "6E") return "6E"
                                                        if (g === "6") return "6"
                                                        if (g === "5") return "5"
                                                        if (g === "4") return "4"
                                                        return ""
                                                    }
                                                    color: root.genColor(modelData.gen || "")
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true
                                                }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter; width: 46
                                                    text: modelData.freq ? modelData.freq + "" : ""
                                                    color: {
                                                        var f = modelData.freq || 0
                                                        if (f >= 5925) return "#bb86fc"
                                                        if (f >= 5000) return "#42a5f5"
                                                        return "#8d6e63"
                                                    }
                                                    font.family: "DejaVuSansM Nerd Font Mono"
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                }
                                                Text { anchors.verticalCenter: parent.verticalCenter; width: 36; text: modelData.channel ? "ch" + modelData.channel : ""; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny }
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter; width: 56
                                                    text: { var w = modelData.channel_width || ""; return w.replace(/ MHz/g, "M").replace("20 or 40", "20/40") }
                                                    color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                }
                                                Text { anchors.verticalCenter: parent.verticalCenter; width: 22; text: modelData.streams > 0 ? modelData.streams + "SS" : ""; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny }
                                                Text { anchors.verticalCenter: parent.verticalCenter; width: modelData.mu_mimo ? 18 : 0; visible: modelData.mu_mimo; text: "MU"; color: "#4dd0e1"; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true }
                                                Text { anchors.verticalCenter: parent.verticalCenter; width: modelData.twt ? 22 : 0; visible: modelData.twt; text: "TWT"; color: "#66bb6a"; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true }
                                                Text { anchors.verticalCenter: parent.verticalCenter; width: modelData.wps ? 22 : 0; visible: modelData.wps; text: "WPS"; color: "#ffb74d"; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true }
                                            }

                                            Text {
                                                id: apSignalText
                                                anchors.right: parent.right
                                                anchors.rightMargin: 4
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 32
                                                text: modelData.signal_dbm !== undefined ? modelData.signal_dbm + "" : ""
                                                color: root.signalColorForPct(modelData.signal)
                                                font.family: AppConfig.Config.theme.fontFamily
                                                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true
                                                horizontalAlignment: Text.AlignRight
                                            }

                                            MouseArea {
                                                id: apMA
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                onClicked: {
                                                    if (modelData.active) return
                                                    var sec = modelData.security || ""
                                                    if (sec === "Open" || sec === "" || modelData.known)
                                                        root.connectToWifi(modelData.ssid, modelData.bssid, "", modelData.known)
                                                    else
                                                        root.passwordInputBssid = (root.passwordInputBssid === modelData.bssid) ? "" : modelData.bssid
                                                }
                                            }
                                        }

                                        // Password input
                                        Item {
                                            width: parent.width
                                            height: root.passwordInputBssid === modelData.bssid ? 22 : 0
                                            visible: height > 0; clip: true
                                            Behavior on height { NumberAnimation { duration: 150 } }
                                            Row {
                                                anchors.fill: parent; anchors.leftMargin: 14; spacing: 4
                                                Text { anchors.verticalCenter: parent.verticalCenter; text: String.fromCodePoint(0xF0341); color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall }
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter; width: 120; height: 16; radius: 3
                                                    color: Qt.rgba(1,1,1,0.08); border.color: Qt.rgba(1,1,1,0.15); border.width: 1
                                                    TextInput {
                                                        id: pwInput; anchors.fill: parent; anchors.margins: 3
                                                        color: Helpers.Colors.textDefault; font.family: "DejaVuSansM Nerd Font Mono"; font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                                        echoMode: TextInput.Password; clip: true
                                                        onAccepted: root.connectToWifi(modelData.ssid, modelData.bssid, text, modelData.known)
                                                        Component.onCompleted: if (root.passwordInputBssid === modelData.bssid) forceActiveFocus()
                                                    }
                                                }
                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter; width: 36; height: 16; radius: 3
                                                    color: connectBtnMA.containsMouse ? "#42a5f5" : Qt.rgba(1,1,1,0.10)
                                                    Text { id: connectBtnText; anchors.centerIn: parent; text: root.wifiConnecting ? "…" : "Go"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall; font.bold: true }
                                                    MouseArea { id: connectBtnMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !root.wifiConnecting; onClicked: root.connectToWifi(modelData.ssid, modelData.bssid, pwInput.text, modelData.known) }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Traffic bar graph (right; expands when wifi hidden) ──
                Rectangle {
                    width: root.wifiEnabled ? (parent.width - 10) / 2 : parent.width
                    Behavior on width { NumberAnimation { duration: 200 } }
                    height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.04)
                    radius: 8

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        Row {
                            width: parent.width
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(0xF04E1)
                                color: "#90caf9"
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Traffic"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                font.bold: true
                            }
                            Item { width: 1; height: 1 }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: -2
                                Text {
                                    text: {
                                        var h = root.trafficHistory;
                                        if (h.length === 0) return "↑ —";
                                        return "↑ " + root.fmtRate(h[h.length - 1].tx);
                                    }
                                    color: "#ff9800"
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                }
                                Text {
                                    text: {
                                        var h = root.trafficHistory;
                                        if (h.length === 0) return "↓ —";
                                        return "↓ " + root.fmtRate(h[h.length - 1].rx);
                                    }
                                    color: "#42a5f5"
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                }
                            }
                            Item { width: 8; height: 1 }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: -2
                                Text {
                                    text: {
                                        var h = root.trafficHistory;
                                        if (h.length === 0) return "max ↑ —";
                                        var m = 0;
                                        for (var i = 0; i < h.length; i++)
                                            if (h[i].tx > m) m = h[i].tx;
                                        return "max ↑ " + root.fmtRate(m);
                                    }
                                    color: Qt.rgba(1, 0.6, 0, 0.6)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                }
                                Text {
                                    text: {
                                        var h = root.trafficHistory;
                                        if (h.length === 0) return "max ↓ —";
                                        var m = 0;
                                        for (var i = 0; i < h.length; i++)
                                            if (h[i].rx > m) m = h[i].rx;
                                        return "max ↓ " + root.fmtRate(m);
                                    }
                                    color: Qt.rgba(0.26, 0.65, 0.96, 0.6)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                }
                            }
                        }

                        Canvas {
                            id: trafficGraph
                            width: parent.width
                            height: parent.height - 24

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                var h = root.trafficHistory;
                                if (h.length === 0) return;

                                var rawMax = 0;
                                for (var i = 0; i < h.length; i++) {
                                    if (h[i].tx > rawMax) rawMax = h[i].tx;
                                    if (h[i].rx > rawMax) rawMax = h[i].rx;
                                }
                                // Nice auto-scale ceiling with headroom
                                var maxVal;
                                if (rawMax <= 0) maxVal = 1024;
                                else if (rawMax < 1024) maxVal = 1024;
                                else if (rawMax < 10240) maxVal = Math.ceil(rawMax / 1024) * 1024;
                                else if (rawMax < 102400) maxVal = Math.ceil(rawMax / 10240) * 10240;
                                else if (rawMax < 1048576) maxVal = Math.ceil(rawMax / 102400) * 102400;
                                else maxVal = Math.ceil(rawMax / 1048576) * 1048576;
                                if (maxVal < rawMax * 1.1) maxVal = Math.ceil(rawMax * 1.15);

                                var halfH = height / 2;
                                var barW = width / root.trafficMaxHistory;
                                var offset = width - h.length * barW;

                                // Grid: center + quarter lines
                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.06);
                                ctx.lineWidth = 1;
                                for (var g = 0.25; g <= 0.75; g += 0.25) {
                                    ctx.beginPath();
                                    ctx.moveTo(0, halfH - g * halfH);
                                    ctx.lineTo(width, halfH - g * halfH);
                                    ctx.stroke();
                                    ctx.beginPath();
                                    ctx.moveTo(0, halfH + g * halfH);
                                    ctx.lineTo(width, halfH + g * halfH);
                                    ctx.stroke();
                                }
                                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.10);
                                ctx.beginPath();
                                ctx.moveTo(0, halfH);
                                ctx.lineTo(width, halfH);
                                ctx.stroke();

                                for (var i = 0; i < h.length; i++) {
                                    var x = offset + i * barW;
                                    var txR = Math.min(1, h[i].tx / maxVal);
                                    var rxR = Math.min(1, h[i].rx / maxVal);

                                    if (txR > 0) {
                                        var txH = txR * halfH;
                                        var ta = 0.3 + 0.7 * txR;
                                        ctx.fillStyle = "rgba(255, 152, 0, " + ta + ")";
                                        ctx.fillRect(x, halfH - txH, Math.max(1, barW - 0.3), txH);
                                    }
                                    if (rxR > 0) {
                                        var rxH = rxR * halfH;
                                        var ra = 0.3 + 0.7 * rxR;
                                        ctx.fillStyle = "rgba(66, 165, 245, " + ra + ")";
                                        ctx.fillRect(x, halfH, Math.max(1, barW - 0.3), rxH);
                                    }
                                }

                                ctx.fillStyle = "rgba(255,255,255,0.35)";
                                ctx.font = "10px '" + AppConfig.Config.theme.fontFamily + "'";
                                ctx.textAlign = "left";
                                ctx.fillText("↑ " + root.fmtRate(maxVal), 2, 10);
                                ctx.fillText(root.fmtRate(maxVal / 2), 2, halfH * 0.5 + 3);
                                ctx.fillText(root.fmtRate(maxVal / 2), 2, halfH * 1.5 + 3);
                                ctx.fillText("↓ " + root.fmtRate(maxVal), 2, height - 3);
                            }
                        }
                    }
                }
            }

            // ── Bluetooth ────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: btContent.implicitHeight + 20
                color: Qt.rgba(1, 1, 1, 0.04)
                radius: 8

                Column {
                    id: btContent
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 4

                    // Header
                    Item {
                        width: parent.width
                        height: 20

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String.fromCodePoint(0xF00AF)
                                color: root.btController && root.btController.powered ? "#42a5f5" : Helpers.Colors.disconnected
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 14
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Bluetooth"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                font.bold: true
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.btController && root.btController.name
                                text: root.btController ? root.btController.name : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.btDevices.length > 0
                                width: btCountText.implicitWidth + 8
                                height: 16; radius: 3
                                color: Qt.rgba(1, 1, 1, 0.10)
                                Text {
                                    id: btCountText
                                    anchors.centerIn: parent
                                    text: root.btDevices.length
                                    color: Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    font.bold: true
                                }
                            }
                            // Discoverable badge
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.btController && root.btController.discoverable
                                width: discLabel.implicitWidth + 8
                                height: 14; radius: 3
                                color: Qt.rgba(0.26, 0.65, 0.96, 0.15)
                                border.color: "#42a5f5"; border.width: 1
                                Text {
                                    id: discLabel
                                    anchors.centerIn: parent
                                    text: "Discoverable"
                                    color: "#42a5f5"
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    font.bold: true
                                }
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            // Discoverable toggle
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.btController && root.btController.powered
                                text: String.fromCodePoint(0xF0124)
                                color: btDiscMA.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 14
                                MouseArea {
                                    id: btDiscMA
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: btToggleDiscoverableProc.running = true
                                }
                            }

                            // Scan toggle
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.btController && root.btController.powered
                                width: btScanLabel.implicitWidth + 12; height: 16; radius: 3
                                color: {
                                    var scanning = root.btController && root.btController.discovering;
                                    if (btScanToggleMA.containsMouse) return scanning ? "#ef5350" : "#42a5f5";
                                    return scanning ? Qt.rgba(0.26, 0.65, 0.96, 0.2) : Qt.rgba(1,1,1,0.10);
                                }
                                Text {
                                    id: btScanLabel
                                    anchors.centerIn: parent
                                    text: root.btController && root.btController.discovering ? "Scanning" : "Scan"
                                    color: root.btController && root.btController.discovering ? "#42a5f5" : Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    font.bold: true
                                }
                                MouseArea {
                                    id: btScanToggleMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: btToggleScanProc.running = true
                                }
                            }
                        }
                    }

                    // Power toggle
                    Rectangle {
                        anchors.right: parent.right
                        width: 34; height: 16; radius: 8
                        color: root.btController && root.btController.powered ? "#42a5f5" : Qt.rgba(1, 1, 1, 0.15)
                        Behavior on color { ColorAnimation { duration: 200 } }
                        Rectangle {
                            width: 12; height: 12; radius: 6
                            anchors.verticalCenter: parent.verticalCenter
                            x: root.btController && root.btController.powered ? parent.width - width - 2 : 2
                            color: "#ffffff"
                            Behavior on x { NumberAnimation { duration: 200 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: btTogglePowerProc.running = true
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

                    // Error message
                    Text {
                        visible: root.btActionError !== ""
                        text: String.fromCodePoint(0xF0029) + " " + root.btActionError
                        color: "#ef5350"
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        width: parent.width
                        elide: Text.ElideRight
                    }

                    // Powered off state
                    Text {
                        visible: !(root.btController && root.btController.powered)
                        text: root.btController ? "Bluetooth off" : "No controller"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                    }

                    // Device list
                    Column {
                        visible: root.btController && root.btController.powered
                        width: parent.width
                        spacing: 1

                        Text {
                            visible: root.btDevices.length === 0
                            text: root.btScanLoading ? "Scanning…" : "No devices"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        }

                        Repeater {
                            model: root.btDevices
                            Rectangle {
                                required property var modelData
                                width: parent.width
                                height: 26
                                radius: 2
                                color: {
                                    if (modelData.connected) return Qt.rgba(0.05, 0.68, 0.29, 0.12)
                                    if (btDevMA.containsMouse) return Qt.rgba(1,1,1,0.08)
                                    return "transparent"
                                }

                                Rectangle {
                                    visible: modelData.connected
                                    width: 2; radius: 1
                                    anchors.top: parent.top; anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.topMargin: 2; anchors.bottomMargin: 2
                                    color: "#42a5f5"
                                }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6
                                    anchors.right: btDevRight.left
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.btIconForType(modelData.icon)
                                        color: modelData.connected ? "#42a5f5" : Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.name
                                        color: modelData.connected ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                        font.bold: modelData.connected
                                        elide: Text.ElideRight
                                        width: Math.min(implicitWidth, 200)
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.mac
                                        color: Helpers.Colors.textMuted
                                        font.family: "DejaVuSansM Nerd Font Mono"
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    }

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: modelData.paired
                                        width: pairedLabel.implicitWidth + 8
                                        height: 14; radius: 3
                                        color: Qt.rgba(0.30, 0.69, 0.31, 0.15)
                                        border.color: "#66bb6a"; border.width: 1
                                        Text {
                                            id: pairedLabel
                                            anchors.centerIn: parent
                                            text: "Paired"
                                            color: "#66bb6a"
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: modelData.battery !== null && modelData.battery !== undefined
                                        text: modelData.battery !== null ? String.fromCodePoint(0xF0079) + " " + modelData.battery + "%" : ""
                                        color: {
                                            var b = modelData.battery || 0;
                                            if (b > 60) return "#66bb6a";
                                            if (b > 20) return "#ffb74d";
                                            return "#ef5350";
                                        }
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    }
                                }

                                Row {
                                    id: btDevRight
                                    anchors.right: parent.right
                                    anchors.rightMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    // Connect/disconnect button
                                    Rectangle {
                                        width: btConnLabel.implicitWidth + 12; height: 16; radius: 3
                                        color: btConnMA.containsMouse
                                            ? (modelData.connected ? "#ef5350" : "#42a5f5")
                                            : Qt.rgba(1,1,1,0.10)
                                        Text {
                                            id: btConnLabel
                                            anchors.centerIn: parent
                                            text: root.btActionLoading ? "…" : (modelData.connected ? "Disconnect" : "Connect")
                                            color: Helpers.Colors.textDefault
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                            font.bold: true
                                        }
                                        MouseArea {
                                            id: btConnMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: !root.btActionLoading
                                            onClicked: {
                                                if (modelData.connected)
                                                    root.btDisconnect(modelData.mac)
                                                else
                                                    root.btConnect(modelData.mac)
                                            }
                                        }
                                    }

                                    // Remove button (only for paired, non-connected)
                                    Rectangle {
                                        visible: modelData.paired && !modelData.connected
                                        width: 16; height: 16; radius: 3
                                        color: btRemMA.containsMouse ? "#ef5350" : Qt.rgba(1,1,1,0.10)
                                        Text {
                                            anchors.centerIn: parent
                                            text: String.fromCodePoint(0xF0156)
                                            color: btRemMA.containsMouse ? "#ffffff" : Helpers.Colors.textMuted
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                        }
                                        MouseArea {
                                            id: btRemMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: !root.btActionLoading
                                            onClicked: root.btRemove(modelData.mac)
                                        }
                                    }
                                }

                                MouseArea {
                                    id: btDevMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.NoButton
                                }
                            }
                        }
                    }
                }
            }

            // ── DNS test + Public IP (side by side) ─────────────────────
            Row {
                width: parent.width
                spacing: 10
                height: 220

            // ── DNS resolution test card ─────────────────────────────────
            Rectangle {
                width: (parent.width - 10) / 2
                height: parent.height
                color: Qt.rgba(1, 1, 1, 0.04)
                radius: 8

                Item {
                    id: dnsTestHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 22

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF0E5C)
                            color: "#90caf9"
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: 14
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "DNS"
                            color: Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                            font.bold: true
                        }
                    }

                    Text {
                        id: dnsTestRefreshBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        transformOrigin: Item.Center
                        text: String.fromCodePoint(0xF0453)
                        color: dnsTestRefreshMA.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                        opacity: root.dnsTestLoading ? 0.5 : 1.0
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: 14
                        RotationAnimation on rotation {
                            running: root.dnsTestLoading
                            from: 0; to: 360
                            duration: 800
                            loops: Animation.Infinite
                        }
                        MouseArea {
                            id: dnsTestRefreshMA
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.dnsTestLoading
                            onClicked: root.refreshDnsTest()
                        }
                    }
                }

                // Table: domains as rows, methods as columns
                Item {
                    id: dnsTable
                    anchors.top: dnsTestHeader.bottom
                    anchors.topMargin: 2
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    anchors.bottomMargin: 4

                    readonly property real colDomain: 90
                    readonly property real colMethod: (width - colDomain) / 3

                    function dnsResult(method, domain) {
                        var m = root.dnsMethods[method]
                        if (!m || !m.tests) return null
                        for (var i = 0; i < m.tests.length; i++)
                            if (m.tests[i].domain === domain) return m.tests[i]
                        return null
                    }

                    readonly property var domains: {
                        var sys = root.dnsMethods["system"]
                        if (sys && sys.tests) return sys.tests.map(function(t) { return t.domain })
                        return ["google.com", "cloudflare.com", "github.com"]
                    }

                    Column {
                        anchors.fill: parent
                        spacing: 1

                        // Column headers with method name + server
                        Row {
                            width: parent.width; height: 30; spacing: 0
                            Item { width: dnsTable.colDomain; height: parent.height }
                            Column {
                                width: dnsTable.colMethod; height: parent.height
                                Text { width: parent.width; text: "System"; color: "#90caf9"; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                Text {
                                    width: parent.width
                                    text: "libc / 127.0.0.53"
                                    color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                            Column {
                                width: dnsTable.colMethod; height: parent.height
                                Text { width: parent.width; text: "Upstream"; color: "#bb86fc"; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                Text {
                                    width: parent.width
                                    text: {
                                        var m = root.dnsMethods["upstream"]
                                        return m ? m.server : "—"
                                    }
                                    color: Helpers.Colors.textMuted; font.family: "DejaVuSansM Nerd Font Mono"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                }
                            }
                            Column {
                                width: dnsTable.colMethod; height: parent.height
                                Text { width: parent.width; text: "External"; color: "#4dd0e1"; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                                Text { width: parent.width; text: "1.1.1.1"; color: Helpers.Colors.textMuted; font.family: "DejaVuSansM Nerd Font Mono"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; horizontalAlignment: Text.AlignHCenter }
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.06) }

                        // Data rows
                        Repeater {
                            model: dnsTable.domains
                            Column {
                                id: dnsRow
                                required property var modelData
                                readonly property string domain: modelData
                                width: parent.width
                                spacing: 0

                                Row {
                                    width: parent.width; height: 18; spacing: 0
                                    Text {
                                        width: dnsTable.colDomain; height: parent.height
                                        text: dnsRow.domain
                                        color: Helpers.Colors.textDefault
                                        font.family: "DejaVuSansM Nerd Font Mono"
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    Repeater {
                                        model: ["system", "upstream", "external"]
                                        Item {
                                            required property var modelData
                                            width: dnsTable.colMethod; height: parent.height
                                            readonly property var r: dnsTable.dnsResult(modelData, dnsRow.domain)
                                            readonly property bool ok: r ? !!r.ok : false
                                            readonly property int ms: r ? (r.time_ms || 0) : 0
                                            Row {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 2
                                                Text {
                                                    text: r ? (ok ? String.fromCodePoint(0xF012C) : String.fromCodePoint(0xF0156)) : "—"
                                                    color: !r ? Helpers.Colors.textMuted : ok ? "#66bb6a" : "#ef5350"
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                }
                                                Text {
                                                    text: ms > 0 ? ms + "ms" : ""
                                                    color: {
                                                        if (!ok) return "#ef5350"
                                                        if (ms <= 30) return "#66bb6a"
                                                        if (ms <= 100) return "#ffb74d"
                                                        return "#f4721a"
                                                    }
                                                    font.family: AppConfig.Config.theme.fontFamily
                                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                    font.bold: true
                                                }
                                            }
                                        }
                                    }
                                }

                                Row {
                                    width: parent.width; height: 14; spacing: 0
                                    Item { width: dnsTable.colDomain; height: parent.height }
                                    Repeater {
                                        model: ["system", "upstream", "external"]
                                        Item {
                                            required property var modelData
                                            width: dnsTable.colMethod; height: parent.height
                                            readonly property var r: dnsTable.dnsResult(modelData, dnsRow.domain)
                                            readonly property bool ok: r ? !!r.ok : false
                                            Text {
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: r && ok ? (r.ip || "") : (r && r.error ? r.error : "")
                                                color: ok ? Helpers.Colors.textMuted : "#ef9a9a"
                                                font.family: "DejaVuSansM Nerd Font Mono"
                                                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                                elide: Text.ElideRight
                                                width: Math.min(implicitWidth, dnsTable.colMethod - 4)
                                            }
                                        }
                                    }
                                }

                                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.03); visible: dnsRow.domain !== "github.com" }
                            }
                        }
                    }
                }
            }

            // ── Public IP / ipinfo card ──────────────────────────────────
            Rectangle {
                width: (parent.width - 10) / 2
                height: parent.height
                color: Qt.rgba(1, 1, 1, 0.04)
                radius: 8

                // Header — globe icon, big IP, country code, flag chips
                Item {
                    id: ipHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 38

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF059F)   // 󰖟 web
                            color: "#4dd0e1"
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: 20
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Public IP"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ipinfo ? root.ipinfo.query : (root.ipinfoLoading ? "loading…" : "—")
                            color: Helpers.Colors.textDefault
                            font.family: "DejaVuSansM Nerd Font Mono"
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                            font.bold: true
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: root.ipinfo && !!root.ipinfo.countryCode
                            width: ccText.implicitWidth + 8
                            height: 16
                            radius: 3
                            color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                id: ccText
                                anchors.centerIn: parent
                                text: root.ipinfo ? root.ipinfo.countryCode : ""
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                font.bold: true
                            }
                        }
                        // Flag chips
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Rectangle {
                                visible: root.ipinfo && root.ipinfo.proxy
                                anchors.verticalCenter: parent.verticalCenter
                                width: vpnT.implicitWidth + 10
                                height: 16
                                radius: 3
                                color: Qt.rgba(1, 0.72, 0.30, 0.18)
                                border.color: "#ffb74d"
                                border.width: 1
                                Text {
                                    id: vpnT
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xF0582) + " VPN"  // 󰖂 shield-lock or similar
                                    color: "#ffb74d"
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    font.bold: true
                                }
                            }
                            Rectangle {
                                visible: root.ipinfo && root.ipinfo.hosting
                                anchors.verticalCenter: parent.verticalCenter
                                width: dcT.implicitWidth + 10
                                height: 16
                                radius: 3
                                color: Qt.rgba(0.73, 0.53, 0.99, 0.18)
                                border.color: "#bb86fc"
                                border.width: 1
                                Text {
                                    id: dcT
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xF1C0F) + " DC"   // 󱰏 server-network
                                    color: "#bb86fc"
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    font.bold: true
                                }
                            }
                            Rectangle {
                                visible: root.ipinfo && root.ipinfo.mobile
                                anchors.verticalCenter: parent.verticalCenter
                                width: mobT.implicitWidth + 10
                                height: 16
                                radius: 3
                                color: Qt.rgba(0.30, 0.81, 0.88, 0.18)
                                border.color: "#4dd0e1"
                                border.width: 1
                                Text {
                                    id: mobT
                                    anchors.centerIn: parent
                                    text: String.fromCodePoint(0xF011F) + " MOBILE"  // 󰄟 cellphone
                                    color: "#4dd0e1"
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // Refresh button
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        transformOrigin: Item.Center
                        text: String.fromCodePoint(0xF0453)
                        color: refreshHover.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                        opacity: root.ipinfoLoading ? 0.5 : 1.0
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: 14
                        RotationAnimation on rotation {
                            running: root.ipinfoLoading
                            from: 0; to: 360
                            duration: 800
                            loops: Animation.Infinite
                        }
                        MouseArea {
                            id: refreshHover
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.ipinfoLoading
                            onClicked: root.refreshIpInfo()
                        }
                    }
                }

                Rectangle {
                    anchors.top: ipHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.07)
                }

                // Two columns: Location · Network
                Row {
                    id: ipColumns
                    anchors.top: ipHeader.bottom
                    anchors.topMargin: 8
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 10
                    spacing: 24

                    // Column 1 — Location
                    Column {
                        width: (parent.width - parent.spacing) / 2
                        spacing: 3

                        SubHeader {
                            iconCode: 0xF034E                   // 󰍎 map-marker
                            iconColor: "#ef5350"
                            label: "Location"
                        }
                        InfoLine {
                            iconCode: 0xF023B                   // 󰈻 flag
                            label: "Country"
                            value: root.ipinfo ? (root.ipinfo.country || "—") : "—"
                            valueBold: true
                            valueExtra: root.ipinfo && root.ipinfo.countryCode ? "(" + root.ipinfo.countryCode + ")" : ""
                        }
                        InfoLine {
                            iconCode: 0xF06EC                   // 󰛬 marker / region
                            label: "Region"
                            value: root.ipinfo ? (root.ipinfo.regionName || "—") : "—"
                        }
                        InfoLine {
                            iconCode: 0xF0683                   // 󰚃 home-city (used for City)
                            label: "City"
                            value: root.ipinfo ? (root.ipinfo.city || "—") : "—"
                        }
                        InfoLine {
                            visible: root.ipinfo && !!root.ipinfo.district
                            iconCode: 0xF0682                   // 󰚂 home-city-outline
                            label: "District"
                            value: root.ipinfo ? root.ipinfo.district : ""
                            height: visible ? 14 : 0
                        }
                        InfoLine {
                            iconCode: 0xF0DA0                   // 󰶠 mailbox
                            label: "ZIP"
                            value: root.ipinfo ? (root.ipinfo.zip || "—") : "—"
                            valueMono: true
                        }
                        InfoLine {
                            iconCode: 0xF07FE                   // 󰟾 earth
                            label: "Continent"
                            value: root.ipinfo ? (root.ipinfo.continent || "—") : "—"
                        }
                        InfoLine {
                            iconCode: 0xF05B1                   // 󰖱 crosshairs-gps
                            label: "Coords"
                            value: root.ipinfo
                                ? (root.ipinfo.lat + ", " + root.ipinfo.lon)
                                : "—"
                            valueMono: true
                        }
                    }

                    // Column 2 — Network / ASN
                    Column {
                        width: (parent.width - parent.spacing) / 2
                        spacing: 3

                        SubHeader {
                            iconCode: 0xF048D                   // 󰒍 network
                            iconColor: "#90caf9"
                            label: "Network"
                        }
                        InfoLine {
                            iconCode: 0xF048D                   // 󰒍 network
                            label: "ISP"
                            value: root.ipinfo ? (root.ipinfo.isp || "—") : "—"
                            valueBold: true
                        }
                        InfoLine {
                            iconCode: 0xF1689                   // 󱚉 office-building
                            label: "Org"
                            value: root.ipinfo ? (root.ipinfo.org || "—") : "—"
                        }
                        InfoLine {
                            iconCode: 0xF0A0E                   // 󰨎 router
                            label: "AS"
                            value: root.ipinfo ? (root.ipinfo.as || "—") : "—"
                            valueMono: true
                        }
                        InfoLine {
                            visible: root.ipinfo && !!root.ipinfo.asname
                            iconCode: 0xF1689                   // 󱚉 office-building
                            label: "AS Name"
                            value: root.ipinfo ? root.ipinfo.asname : ""
                            height: visible ? 14 : 0
                        }
                        InfoLine {
                            visible: root.ipinfo && !!root.ipinfo.reverse
                            iconCode: 0xF0E5C                   // 󰹜 dns
                            label: "Reverse"
                            value: root.ipinfo ? root.ipinfo.reverse : ""
                            valueMono: true
                            height: visible ? 14 : 0
                        }
                    }
                }
            }
            }
        }
        }
    }

    // ─── Inline component: icon | label | value, anchored for alignment ──
    // Columns:  [14 icon] 4 [64 label] 4 [value …]   →  value starts at x=86
    component InfoLine: Item {
        property int iconCode: 0
        property color iconColor: Helpers.Colors.textMuted
        property string label: ""
        property string value: ""
        property bool valueMono: false
        property bool valueBold: false
        property color valueColor: Helpers.Colors.textDefault
        property string valueExtra: ""
        property color valueExtraColor: Helpers.Colors.textMuted

        width: parent ? parent.width : 0
        height: 14

        Text {
            id: _icon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            text: iconCode > 0 ? String.fromCodePoint(iconCode) : ""
            color: iconColor
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            id: _label
            anchors.left: _icon.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 64
            text: label
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            elide: Text.ElideRight
        }
        Text {
            id: _value
            anchors.left: _label.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: value
            color: valueColor
            font.family: valueMono ? "DejaVuSansM Nerd Font Mono" : AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            font.bold: valueBold
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width - 86)
        }
        Text {
            anchors.left: _value.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: valueExtra
            color: valueExtraColor
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            visible: text.length > 0
            elide: Text.ElideRight
            width: Math.max(0, parent.width - 86 - _value.width - 4)
        }
    }

    // ─── Inline component: one DNS resolution test result ───────────────
    // Layout:   [✓/✗] 4 [domain ~110] 4 [ip flex] 4 [time right-aligned]
    component DnsTestLine: Item {
        property var test: ({})         // {domain, ok, ip, time_ms, error}
        width: parent ? parent.width : 0
        height: 14

        readonly property bool ok: !!(test && test.ok)
        readonly property string domain: (test && test.domain) || ""
        readonly property string ip: (test && test.ip) || ""
        readonly property int timeMs: (test && test.time_ms) || 0
        readonly property string err: (test && test.error) || ""

        Text {
            id: dtStatus
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            horizontalAlignment: Text.AlignHCenter
            text: ok ? String.fromCodePoint(0xF012C) : String.fromCodePoint(0xF0156)  // 󰄬 check / 󰅖 close
            color: ok ? "#66bb6a" : "#ef5350"
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
        }
        Text {
            id: dtDomain
            anchors.left: dtStatus.right
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            text: domain
            color: Helpers.Colors.textDefault
            font.family: "DejaVuSansM Nerd Font Mono"
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            elide: Text.ElideRight
        }
        Text {
            id: dtIp
            anchors.left: dtDomain.right
            anchors.leftMargin: 4
            anchors.right: dtTime.left
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: ok ? ip : (err || "—")
            color: ok ? Helpers.Colors.textMuted : "#ef9a9a"
            font.family: ok ? "DejaVuSansM Nerd Font Mono" : AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            elide: Text.ElideRight
        }
        Text {
            id: dtTime
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: timeMs > 0 ? timeMs + " ms" : ""
            color: {
                if (!ok) return "#ef5350";
                if (timeMs <= 30) return "#66bb6a";
                if (timeMs <= 100) return "#ffb74d";
                return "#f4721a";
            }
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            font.bold: true
        }
    }

    // Section sub-header (icon + label) used inside cards
    component SubHeader: Row {
        property int iconCode: 0
        property color iconColor: "#90caf9"
        property string label: ""
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: iconCode > 0 ? String.fromCodePoint(iconCode) : ""
            color: iconColor
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: 13
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: label
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            font.bold: true
        }
    }

    // ─── Inline component: ping panel (graph + stats) ─────────────────────
    component PingPanel: Rectangle {
        id: panel
        property var target: ({ id: "", label: "", iconCode: 0xF059F, host: "" })

        property int currentPing: -1   // -1 = pending, -2 = timeout
        property int avgPing: 0
        property int maxPing: 0
        property int packetCount: 0
        property int packetLoss: 0
        property var history: []

        color: Qt.rgba(1, 1, 1, 0.04)
        radius: 8

        function pingColorFor(val) {
            if (val < 0) return "#ef5350";
            if (val <= 30) return "#66bb6a";
            if (val <= 70) return "#ffb74d";
            if (val <= 120) return "#f4721a";
            return "#ef5350";
        }

        // Round a max-ping value up to the next "nice" axis ceiling so the
        // graph never clips and the user gets human-readable tick labels.
        function niceMax(v) {
            if (v <= 50)   return 50;
            if (v <= 100)  return 100;
            if (v <= 200)  return 200;
            if (v <= 300)  return 300;
            if (v <= 500)  return 500;
            if (v <= 750)  return 750;
            if (v <= 1000) return 1000;
            if (v <= 1500) return 1500;
            if (v <= 2000) return 2000;
            return Math.ceil(v / 1000) * 1000;
        }

        function appendSample(val) {
            var h = panel.history.slice();
            h.push(val);
            if (h.length > root.pingMaxHistory) h.shift();
            panel.history = h;
            panel.packetCount += 1;
            if (val === -2) panel.packetLoss += 1;

            // Recompute average and max over valid samples
            var sum = 0, count = 0, mx = 0;
            for (var i = 0; i < h.length; i++) {
                if (h[i] >= 0) {
                    sum += h[i];
                    count += 1;
                    if (h[i] > mx) mx = h[i];
                }
            }
            panel.avgPing = count > 0 ? Math.round(sum / count) : 0;
            panel.maxPing = mx;
            graph.requestPaint();
        }

        function parseLine(line) {
            // ping -O output: "no answer yet for icmp_seq=X"  or  "...time=12.3 ms"
            var m = line.match(/time=([\d.]+)\s*ms/);
            if (m) {
                panel.currentPing = Math.round(parseFloat(m[1]));
                appendSample(panel.currentPing);
            } else if (line.indexOf("no answer") >= 0
                    || line.indexOf("Destination Host Unreachable") >= 0
                    || line.indexOf("Request timeout") >= 0) {
                panel.currentPing = -2;
                appendSample(-2);
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            // Header
            Row {
                spacing: 6
                width: parent.width
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(panel.target.iconCode)
                    color: Helpers.Colors.textDefault
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: 13
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.target.label
                    color: Helpers.Colors.textDefault
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    font.bold: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.target.host ? "  " + panel.target.host : ""
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                Item { width: 1; height: 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.currentPing === -2 ? "× timeout"
                        : (panel.currentPing < 0 ? "…" : panel.currentPing + " ms")
                    color: panel.pingColorFor(panel.currentPing)
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                    font.bold: true
                }
            }

            // Graph
            Canvas {
                id: graph
                width: parent.width
                height: parent.height - 48

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var h = panel.history;
                    if (h.length === 0) return;

                    // Auto-scale: pick a nice ceiling at or above the
                    // current max sample, but never below 100ms so a calm
                    // line doesn't hug the bottom of the graph.
                    var scaleMax = panel.niceMax(Math.max(100, panel.maxPing));

                    // Horizontal grid at 25/50/75% of scale
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.07);
                    ctx.lineWidth = 1;
                    for (var g = 0.25; g <= 0.75; g += 0.25) {
                        var gy = height - g * height;
                        ctx.beginPath();
                        ctx.moveTo(0, gy);
                        ctx.lineTo(width, gy);
                        ctx.stroke();
                    }

                    var slot = width / root.pingMaxHistory;
                    var offset = width - h.length * slot;

                    // Bars
                    for (var i = 0; i < h.length; i++) {
                        var val = h[i];
                        var x = offset + i * slot;
                        if (val === -2) {
                            ctx.fillStyle = "#ef5350";
                            ctx.fillRect(x, 0, Math.max(1, slot), height);
                            continue;
                        }
                        if (val < 0) continue;
                        var clamped = Math.min(val, scaleMax);
                        var barH = (clamped / scaleMax) * height;
                        ctx.fillStyle = panel.pingColorFor(val);
                        ctx.fillRect(x, height - barH, Math.max(1, slot), barH);
                    }

                    // Y-axis tick labels (top + middle)
                    ctx.fillStyle = "rgba(255,255,255,0.45)";
                    ctx.font = "9px '" + AppConfig.Config.theme.fontFamily + "'";
                    ctx.textAlign = "left";
                    ctx.fillText(scaleMax + " ms", 2, 10);
                    ctx.fillText(Math.round(scaleMax / 2) + " ms", 2, height / 2 - 2);
                }
            }

            // Footer stats
            Row {
                width: parent.width
                spacing: 12

                Column {
                    spacing: -1
                    Text {
                        text: "avg"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                    }
                    Text {
                        text: panel.avgPing > 0 ? panel.avgPing + " ms" : "—"
                        color: panel.pingColorFor(panel.avgPing)
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        font.bold: true
                    }
                }
                Column {
                    spacing: -1
                    Text {
                        text: "max"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                    }
                    Text {
                        text: panel.maxPing > 0 ? panel.maxPing + " ms" : "—"
                        color: Helpers.Colors.textDefault
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    }
                }
                Column {
                    spacing: -1
                    Text {
                        text: "loss"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                    }
                    Text {
                        text: panel.packetCount > 0
                            ? (panel.packetLoss * 100 / panel.packetCount).toFixed(1) + "%"
                            : "—"
                        color: panel.packetLoss === 0 ? "#66bb6a" : "#ef5350"
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        font.bold: panel.packetLoss > 0
                    }
                }
            }
        }

        // Continuous ping pipe — one process per target, no per-tick spawn.
        // -O surfaces missing replies; -W is per-reply timeout; -i 0.5 = 500ms.
        Process {
            id: pingProc
            command: ["ping", "-O", "-W", "3", "-i", "0.333", panel.target.host]
            running: root.popupOpen && panel.target.host !== ""
            // Restart if it dies unexpectedly while popup is still open
            onRunningChanged: {
                if (!running && root.popupOpen && panel.target.host !== "")
                    running = true;
            }
            stdout: SplitParser {
                onRead: data => panel.parseLine(data)
            }
        }

        // Clear history when popup closes so the next open starts fresh.
        Connections {
            target: root
            function onPopupOpenChanged() {
                if (!root.popupOpen) {
                    panel.history = [];
                    panel.currentPing = -1;
                    panel.avgPing = 0;
                    panel.maxPing = 0;
                    panel.packetCount = 0;
                    panel.packetLoss = 0;
                    graph.requestPaint();
                }
            }
        }
    }
}
