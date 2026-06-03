import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "../../core" as Core

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
    property var config: Helpers.ModuleConfig.resolve("network")
    readonly property int effectiveStatusIntervalMs: config.intervalMs

    property int pingServiceRevision: Core.ModuleRegistry.serviceRevision
    readonly property var pingService: {
        pingServiceRevision;
        return Core.ModuleRegistry.serviceInstance("ping");
    }

    property string wifiOutput: ""
    property string ethOutput: ""
    property string activeIface: ""
    property string rxRate: ""
    property string txRate: ""
    property real rxRateNum: 0
    property real txRateNum: 0
    property bool pinned: context && context.service ? context.service.pinned : false
    property bool pingActive: pingService ? pingService.active : false
    // Popup state — left-click toggles; PackagePopup mirrors this to show the popup.
    property bool popupOpen: false
    property string netInfo: ""
    property string wifiName: netInfo ? netInfo.split("|")[0] || "" : ""
    property string netIp: netInfo ? netInfo.split("|")[1] || "" : ""
    property string wifiGen: netInfo ? netInfo.split("|")[2] || "" : ""
    property string wifiBand: netInfo ? netInfo.split("|")[3] || "" : ""
    property bool mlo: netInfo ? netInfo.split("|")[4] === "MLO" : false

    // Graph history (2Hz from daemon = 30s visible)
    property int maxHistory: 60
    property var netHistory: []
    property real maxTxKb: 0
    property real maxRxKb: 0

    property color genColor: {
        if (wifiGen === "7") return "#bb86fc";    // purple
        if (wifiGen === "6E") return "#4dd0e1";   // cyan
        if (wifiGen === "6") return "#66bb6a";    // green
        if (wifiGen === "5") return "#ffa726";    // orange
        if (wifiGen === "4") return "#ef5350";    // red
        return "#757575";                          // gray / legacy
    }

    function formatRate(bytesPerSec) {
        var kb = Math.round(bytesPerSec / 1024);
        return kb.toString();
    }

    readonly property string _sock: AppConfig.Config.daemon.socket

    function refreshStatus() {
        if (!netProc.running)
            netProc.running = true;
        if (!infoProc.running)
            infoProc.running = true;
    }

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

    property int signalStrength: {
        if (!wifiOutput) return -1;
        var parts = wifiOutput.split("|");
        if (parts[3] !== "connected") return -1;
        return parseInt(parts[1]) || 0;
    }

    property bool isWifi: wifiOutput && wifiOutput.split("|")[3] === "connected"
    property bool isEthernet: ethOutput && ethOutput.split("|")[3] === "connected"
    property string connectionStatus: {
        if (!wifiOutput) return "";
        var parts = wifiOutput.split("|");
        return parts[3] || "";
    }
    property bool showStatus: connectionStatus !== "" && connectionStatus !== "connected"
    property bool isConnected: isWifi || isEthernet

    property string connectingName: {
        if (!wifiOutput) return "";
        var parts = wifiOutput.split("|");
        return parts[4] || "";
    }

    property color statusColor: {
        if (connectionStatus === "preparing") return "#ffa726";      // orange
        if (connectionStatus === "configuring") return "#ffa726";    // orange
        if (connectionStatus === "authenticating") return "#ab47bc"; // purple
        if (connectionStatus === "getting-ip") return "#42a5f5";     // blue
        if (connectionStatus === "verifying") return "#42a5f5";      // blue
        if (connectionStatus === "deactivating") return "#ef5350";   // red
        if (connectionStatus === "failed") return "#ef5350";         // red
        if (connectionStatus === "unavailable") return "#757575";    // gray
        return Helpers.Colors.disconnected;
    }

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

    function statusIconText() {
        if (connectionStatus === "preparing") return String.fromCodePoint(0xF04E6);     // nf-md-swap_horizontal
        if (connectionStatus === "configuring") return String.fromCodePoint(0xF0493);   // nf-md-tune
        if (connectionStatus === "authenticating") return String.fromCodePoint(0xF0341); // nf-md-lock_open
        if (connectionStatus === "getting-ip") return String.fromCodePoint(0xF0A5F);    // nf-md-ip_network
        if (connectionStatus === "verifying") return String.fromCodePoint(0xF04E6);     // nf-md-swap_horizontal
        if (connectionStatus === "deactivating") return String.fromCodePoint(0xF05AA);  // nf-md-wifi_off
        if (connectionStatus === "failed") return String.fromCodePoint(0xF0029);        // nf-md-alert
        if (connectionStatus === "unavailable") return String.fromCodePoint(0xF05AA);   // nf-md-wifi_off
        return String.fromCodePoint(0xF092E);                                           // nf-md-wifi_strength_off_outline
    }

    Row {
        id: netRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // Graph with overlaid traffic info
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
                anchors.left: parent.left
                anchors.leftMargin: 2
                spacing: 4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.wifiName
                    color: Helpers.Colors.textDefault
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: 10
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isWifi && root.wifiBand !== ""
                    text: root.wifiBand
                    color: root.wifiBand === "6G" ? "#bb86fc" : root.wifiBand === "5G" ? "#42a5f5" : "#8d6e63"
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: 10
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isWifi && root.wifiGen !== ""
                    text: root.wifiGen
                    color: root.genColor
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.mlo
                    text: "MLO"
                    color: "#bb86fc"
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: 10
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

        Text {
            id: wifiIcon
            anchors.verticalCenter: parent.verticalCenter
            visible: root.isWifi || (!root.isEthernet && !root.showStatus)
            text: root.wifiIconText()
            color: root.iconColor
            opacity: root.isConnected ? 0.9 : 0.6
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon
        }

        // Status icon + network name (non-connected states)
        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showStatus
            spacing: 3

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.statusIconText()
                color: root.statusColor
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: 12
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.connectingName !== ""
                text: root.connectingName
                color: root.statusColor
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: 10
            }
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


    Process {
        id: infoProc
        command: ["bash", "-c", [
            "AIFACE='" + root.activeIface + "'",
            "[ -z \"$AIFACE\" ] && exit 0",
            "IP=$(ip -4 -o addr show dev $AIFACE 2>/dev/null | awk '{print $4}' | cut -d/ -f1)",
            "if [ -d /sys/class/net/$AIFACE/wireless ]; then",
            "  LINK=$(iw dev $AIFACE link 2>/dev/null)",
            "  SSID=$(echo \"$LINK\" | grep -oP 'SSID: \\K.*')",
            "  [ -z \"$SSID\" ] && { echo \"WiFi|${IP}\"; exit 0; }",
            "  FREQ=$(echo \"$LINK\" | grep -oP 'freq: \\K\\d+')",
            "  if echo \"$LINK\" | grep -q 'EHT-'; then GEN='7'",
            "  elif echo \"$LINK\" | grep -q 'HE-'; then",
            "    if [ \"${FREQ:-0}\" -ge 5925 ]; then GEN='6E'; else GEN='6'; fi",
            "  elif echo \"$LINK\" | grep -q 'VHT-'; then GEN='5'",
            "  elif echo \"$LINK\" | grep -q 'HT-'; then GEN='4'",
            "  else GEN='?'; fi",
            "  if [ \"${FREQ:-0}\" -ge 5925 ]; then BAND='6G'",
            "  elif [ \"${FREQ:-0}\" -ge 5000 ]; then BAND='5G'",
            "  else BAND='2.4G'; fi",
            "  if echo \"$LINK\" | grep -qE '^MLD |Link [0-9]+ BSSID'; then MLO='MLO'; else MLO=''; fi",
            "  echo \"${SSID}||${GEN}|${BAND}|${MLO}\"",
            "else",
            "  echo \"|\"",
            "fi"
        ].join("\n")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.netInfo = this.text.trim()
        }
    }

    // Traffic data from daemon stream (persists across QS restarts)
    Process {
        id: daemonStream
        command: ["curl", "-sN", "--unix-socket", root._sock, "http://d/net/stream"]
        running: true
        onRunningChanged: if (!running) running = true
        stdout: SplitParser {
            onRead: data => root.applyDaemonLine(data)
        }
    }

    Process {
        id: netProc
        command: ["bash", "-c", [
            "WIFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^wl' | head -1)",
            "EIFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^(eth|enp|eno|ens)' | head -1)",
            "HAS_OUTPUT=0",
            "# Ethernet (only emitted when link is up)",
            "if [ -n \"$EIFACE\" ] && [ \"$(cat /sys/class/net/$EIFACE/operstate 2>/dev/null)\" = 'up' ]; then",
            "  echo \"ethernet||${EIFACE}|connected\"",
            "  HAS_OUTPUT=1",
            "fi",
            "# WiFi (always emitted when interface exists, even disconnected, for status display)",
            "if [ -n \"$WIFACE\" ]; then",
            "  OPSTATE=$(cat /sys/class/net/$WIFACE/operstate 2>/dev/null)",
            "  if [ \"$OPSTATE\" = 'up' ]; then",
            "    DBM=$(iw dev $WIFACE link 2>/dev/null | grep -oP 'signal: \\K-?\\d+')",
            "    if [ -n \"$DBM\" ]; then",
            "      if [ \"$DBM\" -gt -40 ]; then SIGNAL=100",
            "      elif [ \"$DBM\" -lt -80 ]; then SIGNAL=0",
            "      else SIGNAL=$(( (DBM + 80) * 25 / 10 )); fi",
            "    else SIGNAL=0; fi",
            "    echo \"wifi|${SIGNAL}|${WIFACE}|connected\"",
            "  else",
            "    STATE_NUM=$(nmcli -g GENERAL.STATE device show $WIFACE 2>/dev/null | head -1 | grep -oP '^\\d+')",
            "    CONN=$(nmcli -g GENERAL.CONNECTION device show $WIFACE 2>/dev/null | head -1)",
            "    case \"$STATE_NUM\" in",
            "      20) STATUS='unavailable' ;;",
            "      30) STATUS='disconnected' ;;",
            "      40) STATUS='preparing' ;;",
            "      50) STATUS='configuring' ;;",
            "      60) STATUS='authenticating' ;;",
            "      70) STATUS='getting-ip' ;;",
            "      80|90) STATUS='verifying' ;;",
            "      110) STATUS='deactivating' ;;",
            "      120) STATUS='failed' ;;",
            "      *) STATUS='disconnected' ;;",
            "    esac",
            "    echo \"wifi|0|${WIFACE}|${STATUS}|${CONN}\"",
            "  fi",
            "  HAS_OUTPUT=1",
            "fi",
            "if [ \"$HAS_OUTPUT\" = '0' ]; then",
            "  echo 'disconnected|||disconnected'",
            "fi"
        ].join("\n")]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                var lines = text.length ? text.split("\n") : [];
                var newWifi = "";
                var newEth = "";
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    var kind = line.split("|")[0];
                    if (kind === "wifi") newWifi = line;
                    else if (kind === "ethernet") newEth = line;
                    // "disconnected" fallback: leave both empty
                }
                root.wifiOutput = newWifi;
                root.ethOutput = newEth;

                // Pick the primary interface for traffic / info: prefer ethernet when up.
                var iface = "";
                if (newEth) iface = newEth.split("|")[2] || "";
                else if (newWifi && newWifi.split("|")[3] === "connected") iface = newWifi.split("|")[2] || "";
                if (iface !== root.activeIface) {
                    root.activeIface = iface;
                }
            }
        }
    }

    Timer {
        id: statusTimer
        interval: root.effectiveStatusIntervalMs
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

}
