import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// DNS resolution test card: domains as rows, resolver methods as columns
// (system libc / upstream / external), fed by the daemon's /dns/test route.
Rectangle {
    id: root

    // [system, upstream, external] each with server + tests entries
    property var dnsMethods: ({})
    property bool dnsTestLoading: false

    signal refreshRequested

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
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: String.fromCodePoint(0xF0E5C)
                color: "#90caf9"
                font.pixelSize: 14
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: "DNS"
                font.bold: true
            }
        }

        Components.ThemedText {
            id: dnsTestRefreshBtn
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            transformOrigin: Item.Center
            text: String.fromCodePoint(0xF0453)
            color: dnsTestRefreshMA.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
            opacity: root.dnsTestLoading ? 0.5 : 1.0
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
                onClicked: root.refreshRequested()
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
                    Components.ThemedText { width: parent.width; text: "System"; color: "#90caf9"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true; horizontalAlignment: Text.AlignHCenter }
                    Components.ThemedText {
                        width: parent.width
                        text: "libc / 127.0.0.53"
                        muted: true; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                Column {
                    width: dnsTable.colMethod; height: parent.height
                    Components.ThemedText { width: parent.width; text: "Upstream"; color: "#bb86fc"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true; horizontalAlignment: Text.AlignHCenter }
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
                    Components.ThemedText { width: parent.width; text: "External"; color: "#4dd0e1"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true; horizontalAlignment: Text.AlignHCenter }
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
                                    Components.ThemedText {
                                        text: r ? (ok ? String.fromCodePoint(0xF012C) : String.fromCodePoint(0xF0156)) : "—"
                                        color: !r ? Helpers.Colors.textMuted : ok ? "#66bb6a" : "#ef5350"
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    }
                                    Components.ThemedText {
                                        text: ms > 0 ? ms + "ms" : ""
                                        color: {
                                            if (!ok) return "#ef5350"
                                            if (ms <= 30) return "#66bb6a"
                                            if (ms <= 100) return "#ffb74d"
                                            return "#f4721a"
                                        }
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

    // One DNS resolution test result, preserved from the original popup —
    // currently unused (the table above renders results directly).
    // Layout:   [check] 4 [domain ~110] 4 [ip flex] 4 [time right-aligned]
    component DnsTestLine: Item {
        property var test: ({})         // domain, ok, ip, time_ms, error
        width: parent ? parent.width : 0
        height: 14

        readonly property bool ok: !!(test && test.ok)
        readonly property string domain: (test && test.domain) || ""
        readonly property string ip: (test && test.ip) || ""
        readonly property int timeMs: (test && test.time_ms) || 0
        readonly property string err: (test && test.error) || ""

        Components.ThemedText {
            id: dtStatus
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            horizontalAlignment: Text.AlignHCenter
            text: ok ? String.fromCodePoint(0xF012C) : String.fromCodePoint(0xF0156)  // 󰄬 check / 󰅖 close
            color: ok ? "#66bb6a" : "#ef5350"
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
        Components.ThemedText {
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
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            font.bold: true
        }
    }
}
