import Quickshell.Io
import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
// Composition root: owns the popup state and all daemon fetching, and lays out
// the section components that live in sibling files (PingPanel, WifiCard,
// EthernetCard, TailscaleCard, WifiNetworksPanel, TrafficGraphCard,
// TrafficProcsCard, BluetoothCard, DnsTestCard, PublicIpCard).
Item {
    id: root
    property bool popupOpen: false

    implicitWidth: 1100
    implicitHeight: 920

    // ─── State, populated by the daemon net stream ────────────────────────
    property var wifi: null         // see qs-net-status JSON shape
    property var ethernet: null
    property var tailscale: ({ installed: false })
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
    // system/upstream/external, each with server + tests
    property var dnsMethods: ({})
    property bool dnsTestLoading: false

    // ─── WiFi/Tailscale controls ──────────────────────────────────────────
    property bool wifiEnabled: true
    property var trafficHistory: []
    readonly property int trafficMaxHistory: 300

    // ─── Top processes by traffic (procmon/netprocs, grouped by app) ──────
    property var trafficProcs: []
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
            refreshIpInfo();
            if (root.dnsServers.length > 0)
                refreshDnsTest();
            else
                root._dnsTestPending = true;
            loadWifiNetworks();
            loadBtStatus();
        } else {
            root.trafficHistory = [];
            root.trafficProcs = [];
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
        dnsTestFetch.path = upstream
            ? "/dns/test?upstream=" + encodeURIComponent(upstream)
            : "/dns/test";
        dnsTestFetch.reload();
    }

    function loadWifiNetworks() {
        if (root.wifiScanLoading) return;
        root.wifiScanLoading = true;
        wifiListFetch.reload();
    }

    function scanWifiNetworks() {
        if (root.wifiScanLoading) return;
        root.wifiScanLoading = true;
        wifiScanFetch.reload();
    }

    function connectToWifi(ssid, bssid, password, known) {
        root.wifiConnecting = true;
        root.wifiConnectError = "";
        var payload = {ssid: ssid};
        if (bssid) payload.bssid = bssid;
        if (password) payload.password = password;
        if (known) payload.known = true;
        wifiConnectFetch.body = JSON.stringify(payload);
        wifiConnectFetch.reload();
    }

    // ─── Bluetooth functions ────────────────────────────────────────────
    function loadBtStatus() {
        if (root.btLoading) return;
        root.btLoading = true;
        btStatusFetch.reload();
    }

    function scanBtDevices() {
        if (root.btScanLoading) return;
        root.btScanLoading = true;
        btScanFetch.reload();
    }

    function btConnect(mac) {
        root.btActionLoading = true;
        root.btActionError = "";
        btActionFetch.body = JSON.stringify({mac: mac});
        btActionFetch.path = "/bt/connect";
        btActionFetch.reload();
    }

    function btDisconnect(mac) {
        root.btActionLoading = true;
        root.btActionError = "";
        btActionFetch.body = JSON.stringify({mac: mac});
        btActionFetch.path = "/bt/disconnect";
        btActionFetch.reload();
    }

    function btRemove(mac) {
        root.btActionLoading = true;
        root.btActionError = "";
        btActionFetch.body = JSON.stringify({mac: mac});
        btActionFetch.path = "/bt/remove";
        btActionFetch.reload();
    }

    function refreshIpInfo() {
        if (root.ipinfoLoading) return;
        root.ipinfoLoading = true;
        ipinfoProc.running = true;
    }

    // ─── Long-lived status stream (NDJSON from daemon, 1s cadence) ───────
    Helpers.DaemonStream {
        id: statusStream
        path: "/net/stream"
        active: root.popupOpen
        onLine: d => root.applyStatus(d)
    }

    // ─── Per-process traffic stream (only sampled while popup is open) ────
    Helpers.DaemonStream {
        id: netProcStream
        path: "/procmon/netprocs"
        active: root.popupOpen
        reconnectMs: 500
        onLine: d => root.applyNetProcLine(d)
    }

    function applyStatus(d) {
        if (!d) return;
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
        trafficCard.repaint();
    }

    function applyNetProcLine(d) {
        if (!d) return;
        root.trafficProcs = d.procs || [];
    }

    // ─── ipinfo (public IP geo lookup) ────────────────────────────────────
    // Plain Process (not DaemonFetch): external HTTP with a max-time guard
    // and an echo fallback, not a daemon-socket route.
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
    Helpers.DaemonFetch {
        id: dnsTestFetch
        fetchOnActive: false
        onJson: d => {
            root.dnsTestLoading = false;
            if (d && d.methods) root.dnsMethods = d.methods;
        }
        onFailed: root.dnsTestLoading = false
    }

    // ─── WiFi/Tailscale control fetchers ─────────────────────────────────
    Helpers.DaemonFetch {
        id: wifiToggleFetch
        path: "/net/wifi-toggle"
        method: "POST"
        fetchOnActive: false
    }

    Helpers.DaemonFetch {
        id: tailscaleToggleFetch
        path: "/net/tailscale-toggle"
        method: "POST"
        fetchOnActive: false
    }

    Helpers.DaemonFetch {
        id: wifiListFetch
        path: "/net/wifi-list"
        fetchOnActive: false
        onJson: d => {
            root.wifiScanLoading = false;
            if (d.networks) {
                root.wifiNetworks = d.networks;
                root.wifiNetworkCount = d.count || 0;
            }
        }
        onFailed: root.wifiScanLoading = false
    }

    Helpers.DaemonFetch {
        id: wifiScanFetch
        path: "/net/wifi-scan"
        fetchOnActive: false
        onJson: d => {
            root.wifiScanLoading = false;
            if (d.networks) {
                root.wifiNetworks = d.networks;
                root.wifiNetworkCount = d.count || 0;
            }
        }
        onFailed: root.wifiScanLoading = false
    }

    Helpers.DaemonFetch {
        id: wifiConnectFetch
        path: "/net/wifi-connect"
        method: "POST"
        fetchOnActive: false
        onJson: d => {
            root.wifiConnecting = false;
            if (d.success) {
                root.wifiConnectError = "";
                root.passwordInputBssid = "";
                root.scanWifiNetworks();
            } else {
                root.wifiConnectError = d.message || "Connection failed";
            }
        }
        onFailed: {
            root.wifiConnecting = false;
            root.wifiConnectError = "Connection failed";
        }
    }

    // ─── Bluetooth fetchers ─────────────────────────────────────────────
    Helpers.DaemonFetch {
        id: btStatusFetch
        path: "/bt/status"
        fetchOnActive: false
        onJson: d => {
            root.btLoading = false;
            root.btController = d.controller || null;
            root.btDevices = d.devices || [];
        }
        onFailed: root.btLoading = false
    }

    Helpers.DaemonFetch {
        id: btScanFetch
        path: "/bt/scan"
        fetchOnActive: false
        onJson: d => {
            root.btScanLoading = false;
            if (d.devices) root.btDevices = d.devices;
            root.loadBtStatus();
        }
        onFailed: {
            root.btScanLoading = false;
            root.loadBtStatus();
        }
    }

    Helpers.DaemonFetch {
        id: btActionFetch
        method: "POST"
        fetchOnActive: false
        onJson: d => {
            root.btActionLoading = false;
            if (!d.success) root.btActionError = d.message || "Failed";
            root.loadBtStatus();
        }
        onFailed: {
            root.btActionLoading = false;
            root.btActionError = "Failed";
            root.loadBtStatus();
        }
    }

    Helpers.DaemonFetch {
        id: btTogglePowerFetch
        path: "/bt/toggle-power"
        method: "POST"
        fetchOnActive: false
        onJson: root.loadBtStatus()
        onFailed: root.loadBtStatus()
    }

    Helpers.DaemonFetch {
        id: btToggleDiscoverableFetch
        path: "/bt/toggle-discoverable"
        method: "POST"
        fetchOnActive: false
        onJson: root.loadBtStatus()
        onFailed: root.loadBtStatus()
    }

    Helpers.DaemonFetch {
        id: btToggleScanFetch
        path: "/bt/toggle-scan"
        method: "POST"
        fetchOnActive: false
        onJson: root.loadBtStatus()
        onFailed: root.loadBtStatus()
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

                    Components.ThemedText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF048D)   // network
                        color: Helpers.Colors.accent
                        font.pixelSize: 18
                    }

                    Components.ThemedText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Network"
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
                            popupOpen: root.popupOpen
                            pingMaxHistory: root.pingMaxHistory
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

                    WifiCard {
                        width: (parent.width - 20) / 3
                        height: parent.height
                        wifi: root.wifi
                        wifiEnabled: root.wifiEnabled
                        onToggleWifi: wifiToggleFetch.reload()
                    }

                    EthernetCard {
                        width: (parent.width - 20) / 3
                        height: parent.height
                        ethernet: root.ethernet
                        gatewayInfo: root.gatewayInfo
                        dnsServers: root.dnsServers
                    }

                    TailscaleCard {
                        width: (parent.width - 20) / 3
                        height: parent.height
                        tailscale: root.tailscale
                        onToggleTailscale: tailscaleToggleFetch.reload()
                    }
                }

                // ── WiFi Networks + Network Traffic (side by side) ─────────
                Row {
                    width: parent.width
                    spacing: 10
                    height: 240

                    // WiFi networks list (left, hidden when wifi off)
                    WifiNetworksPanel {
                        visible: root.wifiEnabled
                        width: visible ? (parent.width - 10) / 2 : 0
                        height: parent.height
                        wifiEnabled: root.wifiEnabled
                        wifiNetworks: root.wifiNetworks
                        wifiNetworkCount: root.wifiNetworkCount
                        wifiScanLoading: root.wifiScanLoading
                        wifiConnecting: root.wifiConnecting
                        wifiConnectError: root.wifiConnectError
                        passwordInputBssid: root.passwordInputBssid
                        onScanRequested: root.scanWifiNetworks()
                        onConnectRequested: (ssid, bssid, password, known) => root.connectToWifi(ssid, bssid, password, known)
                        onPasswordInputToggled: bssid => root.passwordInputBssid = bssid
                    }

                    // Traffic bar graph (right; expands when wifi hidden)
                    TrafficGraphCard {
                        id: trafficCard
                        width: root.wifiEnabled ? (parent.width - 10) / 2 : parent.width
                        Behavior on width { NumberAnimation { duration: 200 } }
                        height: parent.height
                        trafficHistory: root.trafficHistory
                        trafficMaxHistory: root.trafficMaxHistory
                    }
                }

                // ── Top processes by traffic ─────────────────────────────────
                TrafficProcsCard {
                    width: parent.width
                    trafficProcs: root.trafficProcs
                }

                // ── Bluetooth ────────────────────────────────────────────────
                BluetoothCard {
                    width: parent.width
                    btController: root.btController
                    btDevices: root.btDevices
                    btScanLoading: root.btScanLoading
                    btActionLoading: root.btActionLoading
                    btActionError: root.btActionError
                    onConnectRequested: mac => root.btConnect(mac)
                    onDisconnectRequested: mac => root.btDisconnect(mac)
                    onRemoveRequested: mac => root.btRemove(mac)
                    onTogglePowerRequested: btTogglePowerFetch.reload()
                    onToggleDiscoverableRequested: btToggleDiscoverableFetch.reload()
                    onToggleScanRequested: btToggleScanFetch.reload()
                }

                // ── DNS test + Public IP (side by side) ─────────────────────
                Row {
                    width: parent.width
                    spacing: 10
                    height: 220

                    DnsTestCard {
                        width: (parent.width - 10) / 2
                        height: parent.height
                        dnsMethods: root.dnsMethods
                        dnsTestLoading: root.dnsTestLoading
                        onRefreshRequested: root.refreshDnsTest()
                    }

                    PublicIpCard {
                        width: (parent.width - 10) / 2
                        height: parent.height
                        ipinfo: root.ipinfo
                        ipinfoLoading: root.ipinfoLoading
                        onRefreshRequested: root.refreshIpInfo()
                    }
                }
            }
        }
    }
}
