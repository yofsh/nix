import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: Math.max(topRow.implicitWidth, botRow.implicitWidth, fallback.implicitWidth) + 12
    implicitHeight: parent ? parent.height : 30

    property var context: null
    property bool popupOpen: false

    property real todayCost: 0
    property real todayTokens: 0
    // Subscription rate-limit utilization (%). -1 = unknown (token expired / offline).
    property real fiveHourPct: -1
    property real weekPct: -1
    readonly property bool hasLimits: fiveHourPct >= 0 || weekPct >= 0

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

    // green < 50% < amber < 80% < red
    function limitColor(pct) {
        if (pct < 0) return Helpers.Colors.textMuted;
        if (pct >= 80) return Helpers.Colors.mutedRed;
        if (pct >= 50) return "#ff9800";
        return Helpers.Colors.accent;
    }

    function fmtPct(pct) {
        return pct < 0 ? "–" : Math.round(pct) + "%";
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
                    var lim = d && d.limits ? d.limits : null;
                    root.fiveHourPct = (lim && lim.fiveHour) ? lim.fiveHour.utilization : -1;
                    root.weekPct = (lim && lim.sevenDay) ? lim.sevenDay.utilization : -1;
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

    // Grouped translucent background, matching the other bar widgets (Claude coral tint).
    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius || 4
        color: Qt.rgba(0.85, 0.46, 0.34, 0.12)
    }

    Column {
        anchors.centerIn: parent
        spacing: -2

        // Top line — today's spend: cost · tokens
        Row {
            id: topRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatCost(root.todayCost)
                color: Helpers.Colors.textDefault
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                font.bold: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.formatTokens(root.todayTokens)
                color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
            }
        }

        // Bottom line — limits: 5-hour % · weekly %, each color-coded
        Row {
            id: botRow
            visible: root.hasLimits
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtPct(root.fiveHourPct)
                color: root.limitColor(root.fiveHourPct)
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                font.bold: true
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "·"
                color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtPct(root.weekPct)
                color: root.limitColor(root.weekPct)
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                font.bold: true
            }
        }

        // Fallback when limits are unavailable, so the widget keeps two lines.
        Text {
            id: fallback
            visible: !root.hasLimits
            anchors.horizontalCenter: parent.horizontalCenter
            text: "—"
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
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
