import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "NetFormat.js" as NetFormat

// Wi-Fi scan list: grouped APs with per-AP detail columns, click to connect,
// inline password input. Data and actions flow through the popup root.
Rectangle {
    id: root

    property bool wifiEnabled: true
    property var wifiNetworks: []
    property int wifiNetworkCount: 0
    property bool wifiScanLoading: false
    property bool wifiConnecting: false
    property string wifiConnectError: ""
    property string passwordInputBssid: ""

    signal scanRequested
    signal connectRequested(var ssid, var bssid, var password, var known)
    signal passwordInputToggled(string bssid)

    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    function signalIconForPct(signal) {
        if (signal >= 75) return String.fromCodePoint(0xF0928);
        if (signal >= 50) return String.fromCodePoint(0xF0925);
        if (signal >= 25) return String.fromCodePoint(0xF0922);
        return String.fromCodePoint(0xF091F);
    }

    function signalColorForPct(signal) {
        if (signal >= 75) return "#4caf50";
        if (signal >= 50) return "#8bc34a";
        if (signal >= 25) return "#ffb74d";
        return "#ef5350";
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4

        Item {
            width: parent.width
            height: 20

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF05A9)
                    color: "#90caf9"
                    font.pixelSize: 14
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Wi-Fi"
                    font.bold: true
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.wifiNetworkCount > 0
                    width: countText.implicitWidth + 8
                    height: 16; radius: 3
                    color: Qt.rgba(1, 1, 1, 0.10)
                    Components.ThemedText {
                        id: countText
                        anchors.centerIn: parent
                        text: root.wifiNetworkCount
                        muted: true
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        font.bold: true
                    }
                }
            }

            Components.ThemedText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                transformOrigin: Item.Center
                text: String.fromCodePoint(0xF0453)
                color: wifiScanRefreshMA.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                opacity: root.wifiScanLoading ? 0.5 : 1.0
                font.pixelSize: 14
                RotationAnimation on rotation {
                    running: root.wifiScanLoading
                    from: 0; to: 360; duration: 800
                    loops: Animation.Infinite
                }
                MouseArea {
                    id: wifiScanRefreshMA
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.wifiScanLoading
                    onClicked: root.scanRequested()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

        Components.ThemedText {
            visible: root.wifiConnectError !== ""
            text: String.fromCodePoint(0xF0029) + " " + root.wifiConnectError
            color: "#ef5350"
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            width: parent.width
            elide: Text.ElideRight
        }

        Flickable {
            width: parent.width
            height: parent.height - 30 - (root.wifiConnectError !== "" ? 16 : 0)
            contentHeight: networkListCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: networkListCol
                width: parent.width
                spacing: 1

                Components.ThemedText {
                    visible: root.wifiNetworks.length === 0
                    text: root.wifiScanLoading ? "Scanning…" : (root.wifiEnabled ? "No networks" : "Wi-Fi off")
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }

                Repeater {
                    model: root.wifiNetworks
                    delegate: Column {
                        id: apDelegate
                        required property var modelData
                        required property int index
                        width: parent.width
                        spacing: 0

                        // ── Group header (SSID label, not clickable) ──
                        Item {
                            visible: modelData.group_first
                            width: parent.width
                            height: visible ? 26 : 0

                            // Gap before group (except first)
                            Components.Divider {
                                visible: apDelegate.index > 0
                                anchors.top: parent.top
                            }

                            Row {
                                anchors.left: parent.left; anchors.leftMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Components.ThemedText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String.fromCodePoint(0xF05A9)
                                    muted: true
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                }
                                Components.ThemedText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.ssid
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                    font.bold: true
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 140)
                                }
                                Components.ThemedText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: modelData.ssid_count > 1
                                    text: modelData.ssid_count + " AP"
                                    muted: true
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                }
                                Components.ThemedText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.security || ""
                                    color: {
                                        var s = modelData.security || ""
                                        if (s === "Open") return "#ef5350"
                                        if (s === "WPA3" || s === "WPA2/3") return "#66bb6a"
                                        return Helpers.Colors.textMuted
                                    }
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !!modelData.known
                                    width: savedLabel.implicitWidth + 8
                                    height: 14; radius: 3
                                    color: Qt.rgba(0.30, 0.69, 0.31, 0.15)
                                    border.color: "#66bb6a"; border.width: 1
                                    Components.ThemedText {
                                        id: savedLabel
                                        anchors.centerIn: parent
                                        text: "Saved"
                                        color: "#66bb6a"
                                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                        font.bold: true
                                    }
                                }
                            }
                        }

                        // ── AP row (clickable, shows BSSID) ──
                        Rectangle {
                            property bool isActive: !!modelData.active
                            property bool isOpen: modelData.security === "Open" || modelData.security === ""
                            width: parent.width
                            height: 24
                            radius: 2
                            color: {
                                if (isActive) return Qt.rgba(0.05, 0.68, 0.29, 0.12)
                                if (isOpen) return Qt.rgba(0.96, 0.26, 0.21, 0.08)
                                if (apMA.containsMouse) return Qt.rgba(1,1,1,0.08)
                                return "transparent"
                            }

                            Rectangle {
                                visible: parent.isOpen && !parent.isActive
                                width: 2; radius: 1
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.topMargin: 2; anchors.bottomMargin: 2
                                color: "#ef5350"
                            }

                            Rectangle {
                                visible: parent.isActive
                                width: 2; radius: 1
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.topMargin: 2; anchors.bottomMargin: 2
                                color: "#66bb6a"
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.right: apSignalText.left
                                anchors.rightMargin: 2
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 6
                                spacing: 0

                                Components.ThemedText { anchors.verticalCenter: parent.verticalCenter; width: 14; text: root.signalIconForPct(modelData.signal); color: root.signalColorForPct(modelData.signal); font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; horizontalAlignment: Text.AlignHCenter }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter; width: 120
                                    text: modelData.bssid || ""
                                    color: modelData.active ? "#66bb6a" : Helpers.Colors.textMuted
                                    font.family: "DejaVuSansM Nerd Font Mono"
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                    elide: Text.ElideRight
                                }
                                Components.ThemedText {
                                    anchors.verticalCenter: parent.verticalCenter; width: 20
                                    text: {
                                        var g = modelData.gen || ""
                                        if (g === "7") return "7"
                                        if (g === "6E") return "6E"
                                        if (g === "6") return "6"
                                        if (g === "5") return "5"
                                        if (g === "4") return "4"
                                        return ""
                                    }
                                    color: NetFormat.genColor(modelData.gen || "") || Helpers.Colors.textMuted
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter; width: 46
                                    text: modelData.freq ? modelData.freq + "" : ""
                                    color: {
                                        var f = modelData.freq || 0
                                        if (f >= 5925) return "#bb86fc"
                                        if (f >= 5000) return "#42a5f5"
                                        return "#8d6e63"
                                    }
                                    font.family: "DejaVuSansM Nerd Font Mono"
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                }
                                Components.ThemedText { anchors.verticalCenter: parent.verticalCenter; width: 36; text: modelData.channel ? "ch" + modelData.channel : ""; muted: true; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny }
                                Components.ThemedText {
                                    anchors.verticalCenter: parent.verticalCenter; width: 56
                                    text: { var w = modelData.channel_width || ""; return w.replace(/ MHz/g, "M").replace("20 or 40", "20/40") }
                                    muted: true; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                }
                                Components.ThemedText { anchors.verticalCenter: parent.verticalCenter; width: 22; text: modelData.streams > 0 ? modelData.streams + "SS" : ""; muted: true; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny }
                                Components.ThemedText { anchors.verticalCenter: parent.verticalCenter; width: modelData.mu_mimo ? 18 : 0; visible: modelData.mu_mimo; text: "MU"; color: "#4dd0e1"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true }
                                Components.ThemedText { anchors.verticalCenter: parent.verticalCenter; width: modelData.twt ? 22 : 0; visible: modelData.twt; text: "TWT"; color: "#66bb6a"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true }
                                Components.ThemedText { anchors.verticalCenter: parent.verticalCenter; width: modelData.wps ? 22 : 0; visible: modelData.wps; text: "WPS"; color: "#ffb74d"; font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true }
                            }

                            Components.ThemedText {
                                id: apSignalText
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                width: 32
                                text: modelData.signal_dbm !== undefined ? modelData.signal_dbm + "" : ""
                                color: root.signalColorForPct(modelData.signal)
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny; font.bold: true
                                horizontalAlignment: Text.AlignRight
                            }

                            MouseArea {
                                id: apMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: modelData.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.active) return
                                    var sec = modelData.security || ""
                                    if (sec === "Open" || sec === "" || modelData.known)
                                        root.connectRequested(modelData.ssid, modelData.bssid, "", modelData.known)
                                    else
                                        root.passwordInputToggled((root.passwordInputBssid === modelData.bssid) ? "" : modelData.bssid)
                                }
                            }
                        }

                        // Password input
                        Item {
                            width: parent.width
                            height: root.passwordInputBssid === modelData.bssid ? 22 : 0
                            visible: height > 0; clip: true
                            Behavior on height { NumberAnimation { duration: 150 } }
                            Row {
                                anchors.fill: parent; anchors.leftMargin: 14; spacing: 4
                                Components.ThemedText { anchors.verticalCenter: parent.verticalCenter; text: String.fromCodePoint(0xF0341); muted: true; font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter; width: 120; height: 16; radius: 3
                                    color: Qt.rgba(1,1,1,0.08); border.color: Qt.rgba(1,1,1,0.15); border.width: 1
                                    TextInput {
                                        id: pwInput; anchors.fill: parent; anchors.margins: 3
                                        color: Helpers.Colors.textDefault; font.family: "DejaVuSansM Nerd Font Mono"; font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                        echoMode: TextInput.Password; clip: true
                                        onAccepted: root.connectRequested(modelData.ssid, modelData.bssid, text, modelData.known)
                                        Component.onCompleted: if (root.passwordInputBssid === modelData.bssid) forceActiveFocus()
                                    }
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter; width: 36; height: 16; radius: 3
                                    color: connectBtnMA.containsMouse ? "#42a5f5" : Qt.rgba(1,1,1,0.10)
                                    Components.ThemedText { id: connectBtnText; anchors.centerIn: parent; text: root.wifiConnecting ? "…" : "Go"; font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall; font.bold: true }
                                    MouseArea { id: connectBtnMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: !root.wifiConnecting; onClicked: root.connectRequested(modelData.ssid, modelData.bssid, pwInput.text, modelData.known) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
