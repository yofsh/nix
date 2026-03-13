import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: netRow.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30

    property string netOutput: ""
    property string activeIface: ""
    property real prevRx: 0
    property real prevTx: 0
    property string rxRate: ""
    property string txRate: ""
    property real rxRateNum: 0
    property real txRateNum: 0
    property bool hovered: false
    property bool pinned: false
    property bool pingActive: false
    property bool expanded: hovered || pinned
    onPinnedChanged: if (pinned) infoProc.running = true
    property string netInfo: ""
    property string wifiName: netInfo ? netInfo.split("|")[0] || "" : ""
    property string netIp: netInfo ? netInfo.split("|")[1] || "" : ""
    property string wifiGen: netInfo ? netInfo.split("|")[2] || "" : ""
    property string wifiBand: netInfo ? netInfo.split("|")[3] || "" : ""
    property bool mlo: netInfo ? netInfo.split("|")[4] === "MLO" : false

    // Graph history
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
        var s = kb.toString();
        while (s.length < 5) s = " " + s;
        return s;
    }

    property real prevTimestamp: 0

    function parseTraffic() {
        if (!root.activeIface) return;
        var rx = parseFloat(rxFile.text().trim()) || 0;
        var tx = parseFloat(txFile.text().trim()) || 0;
        var now = Date.now() / 1000;
        if (root.prevRx > 0 && root.prevTimestamp > 0) {
            var dt = now - root.prevTimestamp;
            if (dt > 0) {
                var rxBps = (rx - root.prevRx) / dt;
                var txBps = (tx - root.prevTx) / dt;
                root.rxRateNum = rxBps / 1024;
                root.txRateNum = txBps / 1024;
                root.rxRate = formatRate(rxBps);
                root.txRate = formatRate(txBps);
            }
        }
        root.prevRx = rx;
        root.prevTx = tx;
        root.prevTimestamp = now;

        // Update history
        var h = root.netHistory.slice();
        h.push({rx: root.rxRateNum, tx: root.txRateNum});
        if (h.length > root.maxHistory)
            h.shift();
        root.netHistory = h;

        // Track max values visible on graph
        var mTx = 0, mRx = 0;
        for (var i = 0; i < h.length; i++) {
            if (h[i].tx > mTx) mTx = h[i].tx;
            if (h[i].rx > mRx) mRx = h[i].rx;
        }
        root.maxTxKb = mTx;
        root.maxRxKb = mRx;

        netGraph.requestPaint();
    }

    property int signalStrength: {
        if (!netOutput) return -1;
        var parts = netOutput.split("|");
        if (parts[0] !== "wifi" || !parts[1]) return -1;
        return parseInt(parts[1]) || 0;
    }

    property bool isWifi: netOutput && netOutput.split("|")[0] === "wifi"
    property bool isEthernet: netOutput && netOutput.split("|")[0] === "ethernet"
    property bool isConnected: isWifi || isEthernet

    property color signalColor: {
        var s = signalStrength;
        if (s < 0) return Helpers.Colors.disconnected;
        if (s < 25) return "#f44336";
        if (s <= 50) return "#ff9800";
        return "#4caf50";
    }

    function netIconText() {
        if (root.isEthernet) return String.fromCodePoint(0xF0200);   // nf-md-ethernet
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

        // Hover info (IP + network name)
        Item {
            id: infoWrapper
            anchors.verticalCenter: parent.verticalCenter
            height: infoRow.implicitHeight
            width: root.expanded ? infoMeasure.implicitWidth + 4 : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Row {
                id: infoRow
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 4
                spacing: 4

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.wifiName
                    color: Helpers.Colors.textDefault
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.netIp
                    color: Helpers.Colors.textMuted
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isWifi && root.wifiBand !== ""
                    text: root.wifiBand
                    color: root.wifiBand === "6G" ? "#bb86fc" : root.wifiBand === "5G" ? "#42a5f5" : "#8d6e63"
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isWifi && root.wifiGen !== ""
                    text: root.wifiGen
                    color: root.genColor
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                    font.bold: true
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.isWifi
                    text: root.signalStrength + "%"
                    color: root.signalColor
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.mlo
                    text: "MLO"
                    color: "#bb86fc"
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -2

                    Text {
                        text: "↑" + Math.round(root.maxTxKb)
                        color: "#ff9800"
                        font.family: "DejaVuSansM Nerd Font"
                        font.pixelSize: 10
                    }

                    Text {
                        text: "↓" + Math.round(root.maxRxKb)
                        color: "#ff9800"
                        font.family: "DejaVuSansM Nerd Font"
                        font.pixelSize: 10
                    }
                }
            }
        }

        // Network icon with signal bar background
        Item {
            id: netIconWrapper
            anchors.verticalCenter: parent.verticalCenter
            width: netIcon.implicitWidth + 6
            height: root.implicitHeight

            Rectangle {
                visible: root.isWifi
                width: parent.width
                height: parent.height
                radius: 1
                color: Qt.rgba(1, 1, 1, 0.1)
            }

            Rectangle {
                visible: root.isWifi
                anchors.bottom: parent.bottom
                width: parent.width
                height: parent.height * (root.signalStrength / 100)
                radius: 1
                color: root.signalColor
                opacity: 0.5
            }

            Text {
                id: netIcon
                anchors.centerIn: parent
                text: root.netIconText()
                color: root.isConnected ? Helpers.Colors.textDefault : Helpers.Colors.disconnected
                opacity: 0.5
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 13
            }
        }

        // Graph with overlaid traffic numbers
        Item {
            id: graphContainer
            anchors.verticalCenter: parent.verticalCenter
            width: netGraph.width
            height: root.implicitHeight

            Canvas {
                id: netGraph
                width: root.maxHistory
                height: parent.height
                opacity: 0.4

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    var h = root.netHistory;
                    if (h.length === 0) return;

                    // Find max value for auto-scaling
                    var maxVal = 1;
                    for (var i = 0; i < h.length; i++) {
                        if (h[i].tx > maxVal) maxVal = h[i].tx;
                        if (h[i].rx > maxVal) maxVal = h[i].rx;
                    }

                    var halfH = height / 2;

                    // Draw newest on the left, oldest on the right
                    // Each bar colored by speed: low=dim, high=bright
                    for (var i = 0; i < h.length; i++) {
                        var si = h.length - 1 - i; // reverse: newest first
                        var txRatio = h[si].tx / maxVal;
                        var rxRatio = h[si].rx / maxVal;

                        // Upload (tx) — top half, grows upward from center
                        var txH = txRatio * halfH;
                        if (txH > 0) {
                            var tr = Math.round(30 + 70 * txRatio);
                            var tg = Math.round(100 + 81 * txRatio);
                            var tb = Math.round(150 + 96 * txRatio);
                            ctx.fillStyle = "rgb(" + tr + "," + tg + "," + tb + ")";
                            ctx.fillRect(i, halfH - txH, 1, txH);
                        }

                        // Download (rx) — bottom half, grows downward from center
                        var rxH = rxRatio * halfH;
                        if (rxH > 0) {
                            var rr = Math.round(20 + 46 * rxRatio);
                            var rg = Math.round(80 + 85 * rxRatio);
                            var rb = Math.round(140 + 105 * rxRatio);
                            ctx.fillStyle = "rgb(" + rr + "," + rg + "," + rb + ")";
                            ctx.fillRect(i, halfH, 1, rxH);
                        }
                    }
                }
            }

            // Traffic numbers + arrows overlaid on the right of graph
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                z: 1
                visible: root.rxRate !== ""

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -2

                    Text {
                        text: root.txRate
                        color: "#64b5f6"
                        font.family: "DejaVuSansM Nerd Font"
                        font.pixelSize: 10
                    }

                    Text {
                        text: root.rxRate
                        color: "#42a5f5"
                        font.family: "DejaVuSansM Nerd Font"
                        font.pixelSize: 10
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: -2

                    Text {
                        text: "↑"
                        color: "#64b5f6"
                        font.pixelSize: 10
                    }

                    Text {
                        text: "↓"
                        color: "#42a5f5"
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // Hidden text to measure target width
    Text {
        id: infoMeasure
        text: root.wifiName + " " + root.netIp + (root.isWifi ? " " + root.wifiBand + " " + root.wifiGen + " " + root.signalStrength + "%" + (root.mlo ? " MLO" : "") : "") + " ↑" + Math.round(root.maxTxKb)
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 10
        visible: false
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.pingActive = !root.pingActive
        onEntered: {
            root.hovered = true;
            infoProc.running = true;
        }
        onExited: root.hovered = false
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
            "  echo \"${SSID}|${IP}|${GEN}|${BAND}|${MLO}\"",
            "else",
            "  echo \"Ethernet|${IP}\"",
            "fi"
        ].join("\n")]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.netInfo = this.text.trim()
        }
    }

    FileView {
        id: rxFile
        path: root.activeIface ? "/sys/class/net/" + root.activeIface + "/statistics/rx_bytes" : ""
        blockLoading: true
    }

    FileView {
        id: txFile
        path: root.activeIface ? "/sys/class/net/" + root.activeIface + "/statistics/tx_bytes" : ""
        blockLoading: true
    }

    Process {
        id: netProc
        command: ["bash", "-c", [
            "WIFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^wl' | head -1)",
            "if [ -n \"$WIFACE\" ] && [ \"$(cat /sys/class/net/$WIFACE/operstate 2>/dev/null)\" = 'up' ]; then",
            "  DBM=$(iw dev $WIFACE link 2>/dev/null | grep -oP 'signal: \\K-?\\d+')",
            "  if [ -n \"$DBM\" ]; then",
            "    if [ \"$DBM\" -gt -40 ]; then SIGNAL=100",
            "    elif [ \"$DBM\" -lt -80 ]; then SIGNAL=0",
            "    else SIGNAL=$(( (DBM + 80) * 25 / 10 )); fi",
            "  else SIGNAL=0; fi",
            "  echo \"wifi|${SIGNAL}|${WIFACE}\"",
            "elif EIFACE=$(ls /sys/class/net/ 2>/dev/null | grep -E '^(eth|enp)' | head -1) && [ -n \"$EIFACE\" ] && [ \"$(cat /sys/class/net/$EIFACE/operstate 2>/dev/null)\" = 'up' ]; then",
            "  echo \"ethernet||${EIFACE}\"",
            "else",
            "  echo 'disconnected||'",
            "fi"
        ].join("\n")]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var out = this.text.trim();
                root.netOutput = out;
                var parts = out.split("|");
                var iface = parts[2] || "";
                if (iface && iface !== root.activeIface) {
                    root.activeIface = iface;
                    root.prevRx = 0;
                    root.prevTx = 0;
                    root.prevTimestamp = 0;
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            netProc.running = true;
            if (root.activeIface) {
                rxFile.reload();
                txFile.reload();
                root.parseTraffic();
            }
        }
    }
}
