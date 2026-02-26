import QtQuick
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: clockText.implicitWidth + 8
    implicitHeight: parent ? parent.height : 30

    property bool altFormat: false
    property string timeStr: ""

    Text {
        id: clockText
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        color: Helpers.Colors.textDefault
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 12
        font.bold: true
        text: root.timeStr
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            var now = new Date();
            if (root.altFormat) {
                var onejan = new Date(now.getFullYear(), 0, 1);
                var dayOfYear = Math.ceil((now - onejan) / 86400000);
                var weekNum = Math.ceil((dayOfYear + onejan.getDay()) / 7);
                root.timeStr = "W" + weekNum + " " + Qt.formatDateTime(now, "ddd dd MMM HH:mm:ss");
            } else {
                root.timeStr = Qt.formatDateTime(now, "ddd dd MMM HH:mm");
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.altFormat = !root.altFormat
    }
}
