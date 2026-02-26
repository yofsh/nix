import QtQuick
import Quickshell.Services.UPower
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: visible ? batCol.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 24
    visible: device && device.ready && !root.isFullyCharged

    property var device: UPower.displayDevice
    property bool hovered: mouseArea.containsMouse
    property bool popupOpen: false

    property bool isFullyCharged: device && device.ready
        && device.state === UPowerDeviceState.FullyCharged

    property bool isCharging: device && device.ready
        && device.state === UPowerDeviceState.Charging

    property string consumptionText: {
        if (!device || !device.ready) return "";
        var rate = Math.abs(device.changeRate).toFixed(1);
        return (root.isCharging ? "↓" : "↑") + rate + "W";
    }

    property string batteryText: {
        if (!device || !device.ready) return "";
        return Math.round(device.percentage * 100).toString();
    }

    property string timeText: {
        if (!device || !device.ready) return "";
        var secs = root.isCharging ? device.timeToFull : device.timeToEmpty;
        if (secs <= 0) return "";
        var h = Math.floor(secs / 3600);
        var m = Math.floor((secs % 3600) / 60);
        return h + ":" + (m < 10 ? "0" : "") + m;
    }

    property color textColor: {
        if (!device || !device.ready) return Helpers.Colors.battery;
        var pct = Math.round(device.percentage * 100);
        if (root.isFullyCharged) return "#a6e3a1";
        if (root.isCharging) return Helpers.Colors.batteryCharging;
        if (pct <= 15) return "#111";
        if (pct <= 30) return "#111";
        return Helpers.Colors.battery;
    }

    property bool hasBgWarning: {
        if (!device || !device.ready) return false;
        var pct = Math.round(device.percentage * 100);
        if (root.isFullyCharged || root.isCharging) return false;
        return pct <= 30;
    }

    property color bgColor: {
        if (!device || !device.ready) return "transparent";
        var pct = Math.round(device.percentage * 100);
        if (root.isCharging) return "transparent";
        if (pct <= 15) return Helpers.Colors.batteryCritical;
        if (pct <= 30) return Helpers.Colors.batteryWarning;
        return "transparent";
    }

    Rectangle {
        anchors.fill: parent
        color: root.bgColor
        radius: 3
        visible: root.hasBgWarning
    }

    Column {
        id: batCol
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.consumptionText
            color: root.textColor
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 9
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0

            Text {
                text: root.batteryText
                color: root.textColor
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 9
            }

            Text {
                text: root.timeText !== "" ? " " + root.timeText : ""
                color: Helpers.Colors.textMuted
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 9
                visible: root.timeText !== ""
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.popupOpen = !root.popupOpen
    }
}
