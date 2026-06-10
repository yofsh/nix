import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Bluetooth section: controller header with power/discoverable/scan controls
// and the device list with connect/disconnect/remove actions.
Rectangle {
    id: root

    property var btController: null
    property var btDevices: []
    property bool btScanLoading: false
    property bool btActionLoading: false
    property string btActionError: ""

    signal connectRequested(string mac)
    signal disconnectRequested(string mac)
    signal removeRequested(string mac)
    signal togglePowerRequested
    signal toggleDiscoverableRequested
    signal toggleScanRequested

    height: btContent.implicitHeight + 20
    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    function btIconForType(icon) {
        if (icon === "audio-headset" || icon === "audio-headphones") return String.fromCodePoint(0xF07CE);
        if (icon === "audio-card") return String.fromCodePoint(0xF075A);
        if (icon === "input-keyboard") return String.fromCodePoint(0xF030C);
        if (icon === "input-mouse") return String.fromCodePoint(0xF037D);
        if (icon === "input-gaming") return String.fromCodePoint(0xF0EB5);
        if (icon === "phone") return String.fromCodePoint(0xF03F2);
        if (icon === "computer") return String.fromCodePoint(0xF0379);
        if (icon === "video-display") return String.fromCodePoint(0xF0379);
        return String.fromCodePoint(0xF00AF);
    }

    Column {
        id: btContent
        anchors.fill: parent
        anchors.margins: 10
        spacing: 4

        // Header
        Item {
            width: parent.width
            height: 20

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF00AF)
                    color: root.btController && root.btController.powered ? "#42a5f5" : Helpers.Colors.disconnected
                    font.pixelSize: 14
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Bluetooth"
                    font.bold: true
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.btController && root.btController.name
                    text: root.btController ? root.btController.name : ""
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.btDevices.length > 0
                    width: btCountText.implicitWidth + 8
                    height: 16; radius: 3
                    color: Qt.rgba(1, 1, 1, 0.10)
                    Components.ThemedText {
                        id: btCountText
                        anchors.centerIn: parent
                        text: root.btDevices.length
                        muted: true
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        font.bold: true
                    }
                }
                // Discoverable badge
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.btController && root.btController.discoverable
                    width: discLabel.implicitWidth + 8
                    height: 14; radius: 3
                    color: Qt.rgba(0.26, 0.65, 0.96, 0.15)
                    border.color: "#42a5f5"; border.width: 1
                    Components.ThemedText {
                        id: discLabel
                        anchors.centerIn: parent
                        text: "Discoverable"
                        color: "#42a5f5"
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        font.bold: true
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                // Discoverable toggle
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.btController && root.btController.powered
                    text: String.fromCodePoint(0xF0124)
                    color: btDiscMA.containsMouse ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                    font.pixelSize: 14
                    MouseArea {
                        id: btDiscMA
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleDiscoverableRequested()
                    }
                }

                // Scan toggle
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.btController && root.btController.powered
                    width: btScanLabel.implicitWidth + 12; height: 16; radius: 3
                    color: {
                        var scanning = root.btController && root.btController.discovering;
                        if (btScanToggleMA.containsMouse) return scanning ? "#ef5350" : "#42a5f5";
                        return scanning ? Qt.rgba(0.26, 0.65, 0.96, 0.2) : Qt.rgba(1,1,1,0.10);
                    }
                    Components.ThemedText {
                        id: btScanLabel
                        anchors.centerIn: parent
                        text: root.btController && root.btController.discovering ? "Scanning" : "Scan"
                        color: root.btController && root.btController.discovering ? "#42a5f5" : Helpers.Colors.textMuted
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        font.bold: true
                    }
                    MouseArea {
                        id: btScanToggleMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleScanRequested()
                    }
                }
            }
        }

        // Power toggle
        Rectangle {
            anchors.right: parent.right
            width: 34; height: 16; radius: 8
            color: root.btController && root.btController.powered ? "#42a5f5" : Qt.rgba(1, 1, 1, 0.15)
            Behavior on color { ColorAnimation { duration: 200 } }
            Rectangle {
                width: 12; height: 12; radius: 6
                anchors.verticalCenter: parent.verticalCenter
                x: root.btController && root.btController.powered ? parent.width - width - 2 : 2
                color: "#ffffff"
                Behavior on x { NumberAnimation { duration: 200 } }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePowerRequested()
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.07) }

        // Error message
        Components.ThemedText {
            visible: root.btActionError !== ""
            text: String.fromCodePoint(0xF0029) + " " + root.btActionError
            color: "#ef5350"
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            width: parent.width
            elide: Text.ElideRight
        }

        // Powered off state
        Components.ThemedText {
            visible: !(root.btController && root.btController.powered)
            text: root.btController ? "Bluetooth off" : "No controller"
            muted: true
        }

        // Device list
        Column {
            visible: root.btController && root.btController.powered
            width: parent.width
            spacing: 1

            Components.ThemedText {
                visible: root.btDevices.length === 0
                text: root.btScanLoading ? "Scanning…" : "No devices"
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            }

            Repeater {
                model: root.btDevices
                Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 26
                    radius: 2
                    color: {
                        if (modelData.connected) return Qt.rgba(0.05, 0.68, 0.29, 0.12)
                        if (btDevMA.containsMouse) return Qt.rgba(1,1,1,0.08)
                        return "transparent"
                    }

                    Rectangle {
                        visible: modelData.connected
                        width: 2; radius: 1
                        anchors.top: parent.top; anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.topMargin: 2; anchors.bottomMargin: 2
                        color: "#42a5f5"
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: btDevRight.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Components.ThemedText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.btIconForType(modelData.icon)
                            color: modelData.connected ? "#42a5f5" : Helpers.Colors.textMuted
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        }

                        Components.ThemedText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.name
                            color: modelData.connected ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            font.bold: modelData.connected
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 200)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.mac
                            color: Helpers.Colors.textMuted
                            font.family: "DejaVuSansM Nerd Font Mono"
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.paired
                            width: pairedLabel.implicitWidth + 8
                            height: 14; radius: 3
                            color: Qt.rgba(0.30, 0.69, 0.31, 0.15)
                            border.color: "#66bb6a"; border.width: 1
                            Components.ThemedText {
                                id: pairedLabel
                                anchors.centerIn: parent
                                text: "Paired"
                                color: "#66bb6a"
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                font.bold: true
                            }
                        }

                        Components.ThemedText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.battery !== null && modelData.battery !== undefined
                            text: modelData.battery !== null ? String.fromCodePoint(0xF0079) + " " + modelData.battery + "%" : ""
                            color: {
                                var b = modelData.battery || 0;
                                if (b > 60) return "#66bb6a";
                                if (b > 20) return "#ffb74d";
                                return "#ef5350";
                            }
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                        }
                    }

                    Row {
                        id: btDevRight
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        // Connect/disconnect button
                        Rectangle {
                            width: btConnLabel.implicitWidth + 12; height: 16; radius: 3
                            color: btConnMA.containsMouse
                                ? (modelData.connected ? "#ef5350" : "#42a5f5")
                                : Qt.rgba(1,1,1,0.10)
                            Components.ThemedText {
                                id: btConnLabel
                                anchors.centerIn: parent
                                text: root.btActionLoading ? "…" : (modelData.connected ? "Disconnect" : "Connect")
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                                font.bold: true
                            }
                            MouseArea {
                                id: btConnMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.btActionLoading
                                onClicked: {
                                    if (modelData.connected)
                                        root.disconnectRequested(modelData.mac)
                                    else
                                        root.connectRequested(modelData.mac)
                                }
                            }
                        }

                        // Remove button (only for paired, non-connected)
                        Rectangle {
                            visible: modelData.paired && !modelData.connected
                            width: 16; height: 16; radius: 3
                            color: btRemMA.containsMouse ? "#ef5350" : Qt.rgba(1,1,1,0.10)
                            Components.ThemedText {
                                anchors.centerIn: parent
                                text: String.fromCodePoint(0xF0156)
                                color: btRemMA.containsMouse ? "#ffffff" : Helpers.Colors.textMuted
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                            }
                            MouseArea {
                                id: btRemMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !root.btActionLoading
                                onClicked: root.removeRequested(modelData.mac)
                            }
                        }
                    }

                    MouseArea {
                        id: btDevMA
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }
        }
    }
}
