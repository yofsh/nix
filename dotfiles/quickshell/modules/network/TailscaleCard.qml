import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Tailscale status card with the start/stop switch and health warnings.
Rectangle {
    id: root

    property var tailscale: ({ installed: false })

    signal toggleTailscale

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

    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    Column {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 4

        Row {
            spacing: 8
            Components.ThemedText {
                text: String.fromCodePoint(0xF08C0)   // lan_connect
                color: root.tailscale && root.tailscale.running ? "#4caf50"
                     : (root.tailscale && root.tailscale.installed ? "#ffb74d" : Helpers.Colors.disconnected)
                font.pixelSize: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Components.ThemedText {
                text: "Tailscale"
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

        Components.ThemedText {
            visible: !(root.tailscale && root.tailscale.installed)
            text: "Not installed"
            muted: true
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
                        Components.ThemedText {
                            x: 0
                            anchors.top: parent.top
                            width: 14
                            text: String.fromCodePoint(0xF0029) // 󰀩 alert
                            color: "#ef5350"
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            horizontalAlignment: Text.AlignHCenter
                        }
                        Components.ThemedText {
                            id: warnText
                            x: 18
                            anchors.top: parent.top
                            width: parent.width - 20
                            text: modelData
                            color: "#ef9a9a"
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10
        width: 34; height: 16; radius: 8
        visible: root.tailscale && root.tailscale.installed
        color: root.tailscale && root.tailscale.running ? "#4caf50" : Qt.rgba(1, 1, 1, 0.15)
        Behavior on color { ColorAnimation { duration: 200 } }
        Rectangle {
            width: 12; height: 12; radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: root.tailscale && root.tailscale.running ? parent.width - width - 2 : 2
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: 200 } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleTailscale()
        }
    }
}
