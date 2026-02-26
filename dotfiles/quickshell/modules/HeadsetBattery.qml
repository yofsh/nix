import QtQuick
import Quickshell.Services.UPower
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: visible ? hbRow.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 30
    visible: hbOutput !== ""

    property string hbOutput: {
        var devs = UPower.devices.values;
        for (var i = 0; i < devs.length; i++) {
            var d = devs[i];
            if (d.type === UPowerDeviceType.Headset
                || d.type === UPowerDeviceType.Headphones) {
                return Math.round(d.percentage * 100) + "";
            }
        }
        return "";
    }

    Row {
        id: hbRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.hbOutput
            color: Helpers.Colors.headsetBattery
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }

        Text {
            id: hbText
            anchors.verticalCenter: parent.verticalCenter
            text: "󰥰"
            color: Helpers.Colors.headsetBattery
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }
    }
}
