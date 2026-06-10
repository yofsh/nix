import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Public IP / ipinfo card: big IP + country/VPN/DC/mobile flag chips, then
// Location and Network/ASN columns from the ip-api.com lookup.
Rectangle {
    id: root

    property var ipinfo: null
    property bool ipinfoLoading: false

    signal refreshRequested

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

            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF059F)   // 󰖟 web
                color: "#4dd0e1"
                font.pixelSize: 20
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Public IP"
                muted: true
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
                Components.ThemedText {
                    id: ccText
                    anchors.centerIn: parent
                    text: root.ipinfo ? root.ipinfo.countryCode : ""
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
                    Components.ThemedText {
                        id: vpnT
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF0582) + " VPN"  // 󰖂 shield-lock or similar
                        color: "#ffb74d"
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
                    Components.ThemedText {
                        id: dcT
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF1C0F) + " DC"   // 󱰏 server-network
                        color: "#bb86fc"
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
                    Components.ThemedText {
                        id: mobT
                        anchors.centerIn: parent
                        text: String.fromCodePoint(0xF011F) + " MOBILE"  // 󰄟 cellphone
                        color: "#4dd0e1"
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        font.bold: true
                    }
                }
            }
        }

        // Refresh button
        Components.ThemedText {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            transformOrigin: Item.Center
            text: String.fromCodePoint(0xF0453)
            color: refreshHover.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
            opacity: root.ipinfoLoading ? 0.5 : 1.0
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
                onClicked: root.refreshRequested()
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
