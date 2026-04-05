import QtQuick
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: Math.max(timeLine.implicitWidth, dateLine.implicitWidth) + 10
    implicitHeight: parent ? parent.height : 22

    property bool altFormat: false

    property string timeStr: ""
    property string dateStr: ""

    Column {
        anchors.centerIn: parent
        spacing: -2

        Text {
            id: timeLine
            anchors.horizontalCenter: parent.horizontalCenter
            color: Helpers.Colors.textDefault
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 11
            font.bold: true
            text: root.timeStr
        }

        Text {
            id: dateLine
            anchors.horizontalCenter: parent.horizontalCenter
            color: Helpers.Colors.textMuted
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 9
            text: root.dateStr
        }
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
                root.timeStr = Qt.formatDateTime(now, "HH:mm:ss");
                root.dateStr = "W" + weekNum + " " + Qt.formatDateTime(now, "ddd dd MMM");
            } else {
                root.timeStr = Qt.formatDateTime(now, "HH:mm");
                root.dateStr = Qt.formatDateTime(now, "ddd dd MMM");
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.altFormat = !root.altFormat
    }
}
