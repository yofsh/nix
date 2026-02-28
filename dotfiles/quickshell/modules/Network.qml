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
                root.rxRate = formatRate((rx - root.prevRx) / dt);
                root.txRate = formatRate((tx - root.prevTx) / dt);
            }
        }
        root.prevRx = rx;
        root.prevTx = tx;
        root.prevTimestamp = now;
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

        // Traffic numbers
        Column {
            id: trafficColumn
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2
            visible: root.rxRate !== ""

            Text {
                id: txText
                text: root.txRate
                color: "#64b5f6"
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 10
            }

            Text {
                id: rxText
                text: root.rxRate
                color: "#42a5f5"
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 10
            }
        }

        // Arrow icons
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: -2
            visible: root.rxRate !== ""

            Text {
                text: "↑"
                color: "#64b5f6"
                font.pixelSize: 12
            }

            Text {
                text: "↓"
                color: "#42a5f5"
                font.pixelSize: 12
            }
        }

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
                    text: root.wifiName
                    color: Helpers.Colors.textDefault
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    text: root.netIp
                    color: Helpers.Colors.textMuted
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    visible: root.isWifi && root.wifiBand !== ""
                    text: root.wifiBand
                    color: root.wifiBand === "6G" ? "#bb86fc" : root.wifiBand === "5G" ? "#42a5f5" : "#8d6e63"
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    visible: root.isWifi && root.wifiGen !== ""
                    text: root.wifiGen
                    color: root.genColor
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                    font.bold: true
                }

                Text {
                    visible: root.isWifi
                    text: root.signalStrength + "%"
                    color: root.signalColor
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }

                Text {
                    visible: root.mlo
                    text: "MLO"
                    color: "#bb86fc"
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
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
    }

    // Hidden text to measure target width
    Text {
        id: infoMeasure
        text: root.wifiName + " " + root.netIp + (root.isWifi ? " " + root.wifiBand + " " + root.wifiGen + " " + root.signalStrength + "%" + (root.mlo ? " MLO" : "") : "")
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
            "IFACE=$(ls /sys/class/net/ | grep -E '^wl' | head -1)",
            "IP=$(ip -4 -o addr show dev " + (root.activeIface || "lo") + " | awk '{print $4}' | cut -d/ -f1)",
            "LINK=$(iw dev ${IFACE:-wlp0s20f3} link 2>/dev/null)",
            "SSID=$(echo \"$LINK\" | grep -oP 'SSID: \\K.*')",
            "if [ -n \"$SSID\" ]; then",
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
            "  echo \"ethernet|${IP}\"",
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
            "if [ -d /sys/class/net/wlan0/wireless ] || [ -d /sys/class/net/wlp* ]; then",
            "  IFACE=$(ls /sys/class/net/ | grep -E '^wl' | head -1)",
            "  if [ -n \"$IFACE\" ] && [ \"$(cat /sys/class/net/$IFACE/operstate 2>/dev/null)\" = 'up' ]; then",
            "    DBM=$(iw dev $IFACE link 2>/dev/null | grep -oP 'signal: \\K-?\\d+')",
            "    if [ -n \"$DBM\" ]; then",
            "      if [ \"$DBM\" -gt -40 ]; then SIGNAL=100",
            "      elif [ \"$DBM\" -lt -80 ]; then SIGNAL=0",
            "      else SIGNAL=$(( (DBM + 80) * 25 / 10 )); fi",
            "    else SIGNAL=0; fi",
            "    echo \"wifi|${SIGNAL}|${IFACE}\"",
            "  else",
            "    echo 'disconnected||'",
            "  fi",
            "elif [ \"$(cat /sys/class/net/eth0/operstate 2>/dev/null || cat /sys/class/net/enp*/operstate 2>/dev/null)\" = 'up' ]; then",
            "  IFACE=$(ls /sys/class/net/ | grep -E '^(eth|enp)' | head -1)",
            "  echo \"ethernet||${IFACE}\"",
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
        interval: 3000
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
