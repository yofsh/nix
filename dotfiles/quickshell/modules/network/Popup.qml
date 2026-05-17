import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

PanelWindow {
    id: root
    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight + AppConfig.Config.theme.popupTopGap
    implicitWidth: 1100
    implicitHeight: 820
    visible: popupOpen
    color: "transparent"

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

    property string gatewayIp: gatewayInfo.gateway || ""

    // ─── ipinfo (public IP) cache ─────────────────────────────────────────
    property var ipinfo: null
    property bool ipinfoLoading: false

    // ─── DNS self-test cache ──────────────────────────────────────────────
    // {system: {server, tests}, upstream: {server, tests}, external: {…}}
    property var dnsMethods: ({})
    property bool dnsTestLoading: false

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
            // Kick a one-shot status fetch immediately so the UI populates
            // before the first 1s tick of the long-lived loop arrives.
            initialStatus.running = true;
            refreshIpInfo();
            refreshDnsTest();
        } else {
            statusLoop.running = false;
        }
    }

    function refreshDnsTest() {
        if (root.dnsTestLoading) return;
        root.dnsTestLoading = true;
        dnsTestProc.running = true;
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

    // ─── Long-lived status process (single pipe, 1s cadence) ──────────────
    Process {
        id: statusLoop
        // bash -lc gives a login-shell PATH and matches how dotfiles/bin
        // scripts are found by other modules in this shell.
        command: ["bash", "-lc", "exec qs-net-status"]
        running: false
        stdout: SplitParser {
            onRead: line => root.applyStatus(line)
        }
    }

    // One-shot fetch so the UI is populated as soon as the popup opens,
    // without waiting for the first iteration of the looping process.
    Process {
        id: initialStatus
        command: ["bash", "-lc", "exec qs-net-status --once"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(this.text)
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

    // ─── DNS self-test (parallel: 3 methods × N domains) ─────────────────
    // Passes the current upstream so we can probe it directly (bypassing
    // libc / systemd-resolved caching) alongside the system path and 1.1.1.1.
    Process {
        id: dnsTestProc
        command: {
            var upstream = (root.dnsServers && root.dnsServers.length > 0)
                ? root.dnsServers[0] : "";
            // Pass upstream as $1 to bash so we don't interpolate user-
            // controlled text into the shell command.
            return upstream
                ? ["bash", "-lc", "exec qs-dns-test --upstream \"$1\"", "bash", upstream]
                : ["bash", "-lc", "exec qs-dns-test"];
        }
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

    // (No auto-refresh — DNS test runs once when the popup opens; user can
    // re-run on demand with the refresh button next to the section header.)

    // ─── Layout ───────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent

        Item {
            id: surface
            anchors.fill: parent
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface { anchors.fill: parent }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 14
            anchors.topMargin: 12
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
                    font.pixelSize: AppConfig.Config.theme.fontSizeMedium
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
                                font.pixelSize: AppConfig.Config.theme.fontSizeBody
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.wifi && root.wifi.iface ? root.wifi.iface : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
                            font.pixelSize: AppConfig.Config.theme.fontSizeBody
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
                                font.pixelSize: AppConfig.Config.theme.fontSizeBody
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.ethernet && root.ethernet.iface ? root.ethernet.iface : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

                        Text {
                            visible: !(root.ethernet && root.ethernet.iface)
                            text: "No ethernet interface"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeBody
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
                                font.pixelSize: AppConfig.Config.theme.fontSizeBody
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
                            font.pixelSize: AppConfig.Config.theme.fontSizeBody
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
                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
                                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── DNS resolution test card ─────────────────────────────────
            Rectangle {
                width: parent.width
                height: 120
                color: Qt.rgba(1, 1, 1, 0.04)
                radius: 8

                // Header — icon + label + per-method summary chips + refresh
                Item {
                    id: dnsTestHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 26

                    function methodOk(m) {
                        var d = root.dnsMethods[m];
                        if (!d || !d.tests) return -1;     // not run yet
                        var ok = 0;
                        for (var i = 0; i < d.tests.length; i++)
                            if (d.tests[i].ok) ok++;
                        return ok === d.tests.length ? 2
                            : (ok === 0 ? 0 : 1);          // 0=red, 1=amber, 2=green
                    }

                    readonly property int sysOk: methodOk("system")
                    readonly property int upOk:  methodOk("upstream")
                    readonly property int extOk: methodOk("external")

                    function statusColor(s) {
                        if (s === 2) return "#66bb6a";
                        if (s === 1) return "#ffb74d";
                        if (s === 0) return "#ef5350";
                        return Helpers.Colors.textMuted;
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String.fromCodePoint(0xF0E5C)   // 󰹜 dns
                            color: "#90caf9"
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: 16
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "DNS resolution test"
                            color: Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeBody
                            font.bold: true
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "·  raw UDP queries bypass libc / resolved cache"
                            color: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                        }
                    }

                    Rectangle {
                        anchors.right: dnsTestRefreshBtn.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 16
                        radius: 3
                        color: "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: {
                                var n = root.dnsMethods["upstream"] ? 3 : 2;
                                var ok = 0;
                                ["system", "upstream", "external"].forEach(function(m) {
                                    if (dnsTestHeader.methodOk(m) === 2) ok++;
                                });
                                return ok + " / " + n;
                            }
                            color: {
                                var states = [dnsTestHeader.sysOk, dnsTestHeader.upOk, dnsTestHeader.extOk]
                                    .filter(function(s){ return s >= 0; });
                                if (states.length === 0) return Helpers.Colors.textMuted;
                                if (states.indexOf(0) >= 0) return "#ef5350";
                                if (states.indexOf(1) >= 0) return "#ffb74d";
                                return "#66bb6a";
                            }
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            font.bold: true
                        }
                    }

                    Rectangle {
                        id: dnsTestRefreshBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 20
                        radius: 4
                        color: dnsTestRefreshMA.containsMouse
                            ? Qt.rgba(1, 1, 1, 0.12)
                            : Qt.rgba(1, 1, 1, 0.05)
                        opacity: root.dnsTestLoading ? 0.5 : 1.0

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF0453)   // 󰑓 refresh
                            color: Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: 13
                        }
                        RotationAnimation on rotation {
                            running: root.dnsTestLoading
                            from: 0; to: 360
                            duration: 800
                            loops: Animation.Infinite
                        }
                        MouseArea {
                            id: dnsTestRefreshMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.dnsTestLoading
                            onClicked: root.refreshDnsTest()
                        }
                    }
                }

                Rectangle {
                    anchors.top: dnsTestHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.07)
                }

                // Three side-by-side columns
                Row {
                    anchors.top: dnsTestHeader.bottom
                    anchors.topMargin: 6
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 8
                    spacing: 14

                    Repeater {
                        model: [
                            {
                                key: "system",
                                title: "System resolver",
                                iconCode: 0xF048D,    // 󰒍 network
                                iconColor: "#90caf9"
                            },
                            {
                                key: "upstream",
                                title: "Upstream (direct)",
                                iconCode: 0xF08F0,    // 󰣰 router
                                iconColor: "#bb86fc"
                            },
                            {
                                key: "external",
                                title: "External 1.1.1.1",
                                iconCode: 0xF059F,    // 󰖟 web
                                iconColor: "#4dd0e1"
                            }
                        ]
                        Column {
                            required property var modelData
                            width: (parent.width - 2 * parent.spacing) / 3
                            spacing: 3

                            // Column header — method name + server in mono
                            Item {
                                width: parent.width
                                height: 16
                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 5
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String.fromCodePoint(modelData.iconCode)
                                        color: modelData.iconColor
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: 13
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.title
                                        color: Helpers.Colors.textDefault
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                        font.bold: true
                                    }
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        var m = root.dnsMethods[modelData.key];
                                        if (!m) return "";
                                        return m.server === "system"
                                            ? "(libc / 127.0.0.53)"
                                            : "@ " + m.server;
                                    }
                                    color: Helpers.Colors.textMuted
                                    font.family: "DejaVuSansM Nerd Font Mono"
                                    font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                                }
                            }

                            // Placeholder while empty
                            Text {
                                visible: !root.dnsMethods[modelData.key]
                                text: modelData.key === "upstream" && (!root.dnsServers || root.dnsServers.length === 0)
                                    ? "no upstream known"
                                    : (root.dnsTestLoading ? "resolving…" : "—")
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            }

                            Repeater {
                                model: root.dnsMethods[modelData.key]
                                    ? root.dnsMethods[modelData.key].tests
                                    : []
                                DnsTestLine {
                                    required property var modelData
                                    test: modelData
                                }
                            }
                        }
                    }
                }
            }

            // ── Public IP / ipinfo card ──────────────────────────────────
            Rectangle {
                width: parent.width
                height: 210
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
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.ipinfo ? root.ipinfo.query : (root.ipinfoLoading ? "loading…" : "—")
                            color: Helpers.Colors.textDefault
                            font.family: "DejaVuSansM Nerd Font Mono"
                            font.pixelSize: AppConfig.Config.theme.fontSizeMedium
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
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
                                    font.pixelSize: AppConfig.Config.theme.fontSizeTiny
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
                                    font.pixelSize: AppConfig.Config.theme.fontSizeTiny
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
                                    font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                                    font.bold: true
                                }
                            }
                        }
                    }

                    // Refresh button
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 22
                        radius: 4
                        color: refreshHover.containsMouse
                            ? Qt.rgba(1, 1, 1, 0.12)
                            : Qt.rgba(1, 1, 1, 0.05)
                        opacity: root.ipinfoLoading ? 0.5 : 1.0

                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF0453)   // 󰑓 refresh
                            color: Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: 14
                        }

                        RotationAnimation on rotation {
                            running: root.ipinfoLoading
                            from: 0; to: 360
                            duration: 800
                            loops: Animation.Infinite
                        }

                        MouseArea {
                            id: refreshHover
                            anchors.fill: parent
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
            font.pixelSize: AppConfig.Config.theme.fontSizeBody
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
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
            font.pixelSize: AppConfig.Config.theme.fontSizeBody
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
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    font.bold: true
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.target.host ? "  " + panel.target.host : ""
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                }
                Item { width: 1; height: 1 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.currentPing === -2 ? "× timeout"
                        : (panel.currentPing < 0 ? "…" : panel.currentPing + " ms")
                    color: panel.pingColorFor(panel.currentPing)
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
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
                        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                    }
                    Text {
                        text: panel.avgPing > 0 ? panel.avgPing + " ms" : "—"
                        color: panel.pingColorFor(panel.avgPing)
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        font.bold: true
                    }
                }
                Column {
                    spacing: -1
                    Text {
                        text: "max"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                    }
                    Text {
                        text: panel.maxPing > 0 ? panel.maxPing + " ms" : "—"
                        color: Helpers.Colors.textDefault
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    }
                }
                Column {
                    spacing: -1
                    Text {
                        text: "loss"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                    }
                    Text {
                        text: panel.packetCount > 0
                            ? (panel.packetLoss * 100 / panel.packetCount).toFixed(1) + "%"
                            : "—"
                        color: panel.packetLoss === 0 ? "#66bb6a" : "#ef5350"
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
