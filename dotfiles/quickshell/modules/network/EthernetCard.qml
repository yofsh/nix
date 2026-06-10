import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "../../helpers/Format.js" as Format

// Ethernet status card plus the shared "Local network" subsection.
Rectangle {
    id: root

    property var ethernet: null
    property var gatewayInfo: ({ gateway: "", dev: "", src: "" })
    property var dnsServers: []

    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    function fmtSpeedMbps(s) {
        if (!s || s <= 0) return "—";
        if (s >= 1000) return (s / 1000).toFixed(1) + " Gb/s";
        return s + " Mb/s";
    }

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        Row {
            spacing: 8
            Components.ThemedText {
                text: String.fromCodePoint(0xF0200)   // ethernet
                color: root.ethernet && root.ethernet.connected ? "#90caf9" : Helpers.Colors.disconnected
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Components.ThemedText {
                text: "Ethernet"
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
            Components.ThemedText {
                text: root.ethernet && root.ethernet.iface ? root.ethernet.iface : ""
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

        Components.ThemedText {
            visible: !(root.ethernet && root.ethernet.iface)
            text: "No ethernet interface"
            muted: true
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
                value: "↑ " + Format.bytes(root.ethernet ? root.ethernet.tx_bytes : 0)
                valueColor: "#64b5f6"
                valueExtra: "↓ " + Format.bytes(root.ethernet ? root.ethernet.rx_bytes : 0)
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
