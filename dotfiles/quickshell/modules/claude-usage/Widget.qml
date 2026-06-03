import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: row.implicitWidth + 6
    implicitHeight: parent ? parent.height : 30

    property var context: null
    property bool popupOpen: false

    property real todayCost: 0
    property real todayTokens: 0

    function formatCost(c) {
        if (c >= 100) return "$" + Math.round(c);
        if (c >= 10) return "$" + c.toFixed(1);
        return "$" + c.toFixed(2);
    }

    function formatTokens(t) {
        if (t >= 1e6) return (t / 1e6).toFixed(1) + "M";
        if (t >= 1e3) return Math.round(t / 1e3) + "k";
        return "" + Math.round(t);
    }

    Process {
        id: loadProc
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/claude-usage/today"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (d && d.today) {
                        root.todayCost = d.today.totalCost || 0;
                        root.todayTokens = d.today.totalTokens || 0;
                    }
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: loadProc.running = true
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰷧" // 󰧑 AI / neural glyph
            color: Helpers.Colors.accent
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatCost(root.todayCost)
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
            font.bold: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatTokens(root.todayTokens)
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.popupOpen = !root.popupOpen
    }
}
