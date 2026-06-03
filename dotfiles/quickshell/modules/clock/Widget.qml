import QtQuick
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: Math.max(timeLine.implicitWidth, dateLine.implicitWidth) + 12
    implicitHeight: parent ? parent.height : 22

    property bool altFormat: false

    property string timeStr: ""
    property string dateStr: ""

    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius || 4
        color: Qt.rgba(0.55, 0.3, 0.85, 0.12)
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        Text {
            id: timeLine
            anchors.horizontalCenter: parent.horizontalCenter
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
            font.bold: true
            text: root.timeStr
        }

        Text {
            id: dateLine
            anchors.horizontalCenter: parent.horizontalCenter
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
