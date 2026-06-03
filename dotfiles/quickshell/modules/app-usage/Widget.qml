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

    property string totalText: "—"
    property int streakSeconds: 0
    property bool onBreak: false

    // Streak color thresholds ("time without break"): the longer you go, the
    // hotter the colour — a gentle nudge to take a break.
    readonly property int streakAmber: 2700  // 45m
    readonly property int streakRed: 4500     // 75m
    readonly property color streakColor: {
        if (onBreak) return Helpers.Colors.textMuted;
        if (streakSeconds >= streakRed) return Helpers.Colors.mutedRed;
        if (streakSeconds >= streakAmber) return "#ffb74d";
        return Helpers.Colors.accent;
    }

    function formatTime(seconds) {
        var h = Math.floor(seconds / 3600);
        var m = Math.floor((seconds % 3600) / 60);
        if (h > 0) return h + "h" + (m > 0 ? m + "m" : "");
        return m + "m";
    }

    Process {
        id: loadProc
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/usage/today"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    if (d) {
                        if (d.totalSeconds > 0) root.totalText = root.formatTime(d.totalSeconds);
                        root.streakSeconds = d.streakSeconds || 0;
                        root.onBreak = !!d.onBreak;
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
            text: root.totalText + ""
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
            font.bold: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "·"
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.onBreak ? " break" : (" " + root.formatTime(root.streakSeconds))
            color: root.streakColor
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
            font.bold: true
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
