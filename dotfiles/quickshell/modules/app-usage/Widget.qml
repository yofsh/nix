import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: Math.max(topLine.implicitWidth, botLine.implicitWidth) + 12
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

    // Grouped translucent background, matching the other bar widgets (gold tint).
    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius || 4
        color: Qt.rgba(0.95, 0.7, 0.2, 0.12)
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        // Top line — total time on PC today
        Text {
            id: topLine
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.totalText
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
            font.bold: true
        }

        // Bottom line — current streak since last break (or "break" when idle)
        Text {
            id: botLine
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.onBreak ? "break" : root.formatTime(root.streakSeconds)
            color: root.streakColor
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
