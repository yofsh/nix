import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../helpers/Format.js" as Format
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

    Helpers.DaemonFetch {
        path: "/claude-usage/today"
        intervalMs: 30000
        onJson: d => {
            if (d && d.today) {
                root.todayCost = d.today.totalCost || 0;
                root.todayTokens = d.today.totalTokens || 0;
            }
            var lim = d && d.limits ? d.limits : null;
            root.fiveHourPct = (lim && lim.fiveHour) ? lim.fiveHour.utilization : -1;
            root.weekPct = (lim && lim.sevenDay) ? lim.sevenDay.utilization : -1;
        }
    }

    // Grouped translucent background, matching the other bar widgets (Claude coral tint).
    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius
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

            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: Format.cost(root.todayCost)
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                font.bold: true
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: Format.tokens(root.todayTokens)
                muted: true
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
            }
        }

        // Bottom line — limits: 5-hour % · weekly %, each color-coded
        Row {
            id: botRow
            visible: root.hasLimits
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtPct(root.fiveHourPct)
                color: root.limitColor(root.fiveHourPct)
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                font.bold: true
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: "·"
                muted: true
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
            }
            Components.ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.fmtPct(root.weekPct)
                color: root.limitColor(root.weekPct)
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                font.bold: true
            }
        }

        // Fallback when limits are unavailable, so the widget keeps two lines.
        Components.ThemedText {
            id: fallback
            visible: !root.hasLimits
            anchors.horizontalCenter: parent.horizontalCenter
            text: "—"
            muted: true
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
