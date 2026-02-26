import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: tempText.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30

    property int tempC: {
        var raw = tempFile.text().trim();
        return raw ? Math.round(parseInt(raw) / 1000) : 0;
    }
    property bool isCritical: tempC >= 75

    FileView {
        id: tempFile
        path: "/sys/class/thermal/thermal_zone4/temp"
        blockLoading: true
    }

    Text {
        id: tempText
        anchors.verticalCenter: parent.verticalCenter
        text: root.tempC > 0 ? root.tempC + "°" : ""
        color: root.isCritical ? Helpers.Colors.temperatureCritical : Helpers.Colors.textDefault
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 12
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: tempFile.reload()
    }
}
