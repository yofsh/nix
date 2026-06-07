import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "../../core" as Core

// Pure consumer of the qs-daemon `net/stream`. The daemon is the single source
// of truth for network status (see dotfiles/quickshell/CLAUDE.md "Daemon is the
// single source"); this widget spawns NOTHING. The bar deliberately shows only
// the essentials — signal icon, connection type, coarse status, traffic — not
// SSID/band/gen/MLO/IP (those live in the popup).
Item {
    id: root
    implicitWidth: netRow.implicitWidth + 8
    implicitHeight: parent ? parent.height : 30

    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius || 4
        color: Qt.rgba(0.2, 0.5, 0.9, 0.12)
    }

    property var context: null

    property int pingServiceRevision: Core.ModuleRegistry.serviceRevision
    readonly property var pingService: {
        pingServiceRevision;
        return Core.ModuleRegistry.serviceInstance("ping");
    }

    // ─── State from the daemon stream ─────────────────────────────────────
    property var wifi: null         // d.wifi  (see net-status.ts WifiStatus)
    property var ethernet: null     // d.ethernet
    property string rxRate: ""
    property string txRate: ""
    property real rxRateNum: 0
    property real txRateNum: 0
    property bool pinned: context && context.service ? context.service.pinned : false
    property bool pingActive: pingService ? pingService.active : false
    // Popup state — left-click toggles; PackagePopup mirrors this to show the popup.
    property bool popupOpen: false

    // Graph history (2Hz from daemon = 30s visible)
    property int maxHistory: 60
    property var netHistory: []
    property real maxTxKb: 0
    property real maxRxKb: 0

    function formatRate(bytesPerSec) {
        var kb = Math.round(bytesPerSec / 1024);
        return kb.toString();
    }

    // dBm → 0..100% (matches the daemon's dbmToPct).
    function dbmToPct(dbm) {
        if (dbm === undefined || dbm === null) return 0;
        if (dbm >= -40) return 100;
        if (dbm <= -80) return 0;
        return Math.round((dbm + 80) * 2.5);
    }

    readonly property string _sock: AppConfig.Config.daemon.socket

    function applyTrafficTick(rxBytes, txBytes) {
        root.rxRateNum = rxBytes / 1024;
        root.txRateNum = txBytes / 1024;
        root.rxRate = formatRate(rxBytes);
        root.txRate = formatRate(txBytes);

        var h = root.netHistory.slice();
        h.push({rx: root.rxRateNum, tx: root.txRateNum});
        if (h.length > root.maxHistory) h.shift();
        root.netHistory = h;

        var mTx = 0, mRx = 0;
        for (var i = 0; i < h.length; i++) {
            if (h[i].tx > mTx) mTx = h[i].tx;
            if (h[i].rx > mRx) mRx = h[i].rx;
        }
        root.maxTxKb = mTx;
        root.maxRxKb = mRx;
        netGraph.requestPaint();
    }

    function applyDaemonLine(raw) {
        if (!raw) return;
        try {
            var d = JSON.parse(raw.trim());

            // Connection state (signal, coarse status, ethernet up/down)
            if (d.wifi !== undefined) root.wifi = d.wifi;
            if (d.ethernet !== undefined) root.ethernet = d.ethernet;

            // Seed history from daemon backlog on first message
            if (d.traffic_history && d.traffic_history.length > 0 && root.netHistory.length === 0) {
                var h = [];
                for (var i = 0; i < d.traffic_history.length; i++) {
                    h.push({rx: d.traffic_history[i].rx / 1024, tx: d.traffic_history[i].tx / 1024});
                }
                if (h.length > root.maxHistory)
                    h = h.slice(h.length - root.maxHistory);
                root.netHistory = h;
                var mTx = 0, mRx = 0;
                for (var j = 0; j < h.length; j++) {
                    if (h[j].tx > mTx) mTx = h[j].tx;
                    if (h[j].rx > mRx) mRx = h[j].rx;
                }
                root.maxTxKb = mTx;
                root.maxRxKb = mRx;
                netGraph.requestPaint();
            }
            // Compute combined rate from all interfaces
            var rxR = 0, txR = 0;
            if (d.wifi && d.wifi.rx_rate) { rxR += d.wifi.rx_rate; txR += (d.wifi.tx_rate || 0); }
            if (d.ethernet && d.ethernet.rx_rate) { rxR += d.ethernet.rx_rate; txR += (d.ethernet.tx_rate || 0); }
            if (rxR > 0 || txR > 0 || root.netHistory.length > 0)
                applyTrafficTick(rxR, txR);
        } catch (e) { /* ignore parse errors */ }
    }

    property bool isWifi: wifi !== null && wifi.connected === true
    property bool isEthernet: ethernet !== null && ethernet.connected === true
    property int signalStrength: isWifi ? dbmToPct(wifi.signal_dbm) : -1

    // Coarse sysfs status: connected | connecting | disconnected (no nmcli).
    property string connectionStatus: wifi ? (wifi.status || "") : ""
    property bool showStatus: connectionStatus === "connecting"
    property bool isConnected: isWifi || isEthernet

    property color signalColor: {
        var s = signalStrength;
        if (s < 0) return Helpers.Colors.disconnected;
        if (s < 25) return "#f44336";
        if (s <= 50) return "#ff9800";
        return "#4caf50";
    }

    property color iconColor: {
        if (!root.isConnected)
            return Helpers.Colors.disconnected;
        return Helpers.Colors.textDefault;
    }

    function wifiIconText() {
        if (!root.isWifi) return String.fromCodePoint(0xF05AA);      // nf-md-wifi_off
        var s = root.signalStrength;
        if (s < 25) return String.fromCodePoint(0xF091F);            // nf-md-wifi_strength_1
        if (s < 50) return String.fromCodePoint(0xF0922);            // nf-md-wifi_strength_2
        if (s < 75) return String.fromCodePoint(0xF0925);            // nf-md-wifi_strength_3
        return String.fromCodePoint(0xF0928);                        // nf-md-wifi_strength_4
    }

    Row {
        id: netRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // Traffic graph with overlaid rate readout
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.maxHistory
            height: root.implicitHeight

            Canvas {
                id: netGraph
                anchors.fill: parent
                opacity: 0.4

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var h = root.netHistory;
                    if (h.length === 0) return;

                    var maxVal = 1;
                    for (var i = 0; i < h.length; i++) {
                        if (h[i].tx > maxVal) maxVal = h[i].tx;
                        if (h[i].rx > maxVal) maxVal = h[i].rx;
                    }

                    var halfH = height / 2;

                    for (var i = 0; i < h.length; i++) {
                        var x = i;
                        var txRatio = h[i].tx / maxVal;
                        var rxRatio = h[i].rx / maxVal;

                        var txH = txRatio * halfH;
                        if (txH > 0) {
                            var tr = Math.round(30 + 70 * txRatio);
                            var tg = Math.round(100 + 81 * txRatio);
                            var tb = Math.round(150 + 96 * txRatio);
                            ctx.fillStyle = "rgb(" + tr + "," + tg + "," + tb + ")";
                            ctx.fillRect(x, halfH - txH, 1, txH);
                        }

                        var rxH = rxRatio * halfH;
                        if (rxH > 0) {
                            var rr = Math.round(20 + 46 * rxRatio);
                            var rg = Math.round(80 + 85 * rxRatio);
                            var rb = Math.round(140 + 105 * rxRatio);
                            ctx.fillStyle = "rgb(" + rr + "," + rg + "," + rb + ")";
                            ctx.fillRect(x, halfH, 1, rxH);
                        }
                    }
                }
            }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 1
                visible: root.rxRate !== ""
                spacing: 0

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    spacing: -2

                    Text {
                        width: parent.width
                        text: root.txRate
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        horizontalAlignment: Text.AlignRight
                    }

                    Text {
                        width: parent.width
                        text: root.rxRate
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -2

                    Text {
                        text: "↑"
                        color: Helpers.Colors.textMuted
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    }

                    Text {
                        text: "↓"
                        color: Helpers.Colors.textMuted
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    }
                }
            }
        }

        // Ethernet icon (shown whenever an ethernet link is up)
        Text {
            id: ethIcon
            anchors.verticalCenter: parent.verticalCenter
            visible: root.isEthernet
            text: String.fromCodePoint(0xF0200)   // nf-md-ethernet
            color: Helpers.Colors.textDefault
            opacity: 0.9
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon
        }

        // Wi-Fi signal icon (or wifi-off when down). Hidden while a connecting
        // indicator is showing and no ethernet is up.
        Text {
            id: wifiIcon
            anchors.verticalCenter: parent.verticalCenter
            visible: root.isWifi || (!root.isEthernet && !root.showStatus)
            text: root.wifiIconText()
            color: root.isWifi ? root.signalColor : root.iconColor
            opacity: root.isConnected ? 0.9 : 0.6
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon
        }

        // Connecting indicator (coarse sysfs state — no SSID/name)
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showStatus
            text: String.fromCodePoint(0xF04E6)   // nf-md-swap_horizontal
            color: "#ffa726"
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                if (root.pingService)
                    root.pingService.active = !root.pingService.active;
                else
                    root.pingActive = !root.pingActive;
            } else {
                root.popupOpen = !root.popupOpen;
            }
        }
    }

    // Single always-on source: the daemon net stream (persists across QS restarts)
    Process {
        id: daemonStream
        command: ["curl", "-sN", "--unix-socket", root._sock, "http://d/net/stream"]
        running: true
        onRunningChanged: if (!running) running = true
        stdout: SplitParser {
            onRead: data => root.applyDaemonLine(data)
        }
    }
}
