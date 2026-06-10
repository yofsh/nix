import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "../../helpers/Format.js" as Format
import "NetFormat.js" as NetFormat

// Wi-Fi connection status card with the radio on/off switch.
Rectangle {
    id: root

    property var wifi: null
    property bool wifiEnabled: true

    signal toggleWifi

    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    function fmtBitrate(mbps) {
        if (!mbps) return "—";
        if (mbps >= 1000) return (mbps / 1000).toFixed(1) + " Gb/s";
        return Math.round(mbps) + " Mb/s";
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

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        Row {
            spacing: 8
            Components.ThemedText {
                text: String.fromCodePoint(root.wifi && root.wifi.connected ? 0xF05A9 : 0xF05AA)
                color: root.wifi && root.wifi.connected ? root.signalColor(root.wifi.signal_dbm) : Helpers.Colors.disconnected
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Components.ThemedText {
                text: "Wi-Fi"
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Components.ThemedText {
                text: root.wifi && root.wifi.iface ? root.wifi.iface : ""
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07); visible: true }

        // Disconnected state
        Components.ThemedText {
            visible: !(root.wifi && root.wifi.connected)
            text: root.wifi && root.wifi.iface ? "Not connected" : "No wireless interface"
            muted: true
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
                valueColor: NetFormat.genColor(root.wifi ? root.wifi.gen : "") || Helpers.Colors.textMuted
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
                value: "↑ " + Format.bytes(root.wifi ? root.wifi.tx_bytes : 0)
                valueColor: "#64b5f6"
                valueExtra: "↓ " + Format.bytes(root.wifi ? root.wifi.rx_bytes : 0)
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
            onClicked: root.toggleWifi()
        }
    }
}
