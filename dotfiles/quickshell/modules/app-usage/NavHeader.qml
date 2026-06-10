import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Popup title row: app icon plus the back/forward date navigation on the left,
// total time and the day/week toggle chip on the right.
Item {
    id: root

    property string viewMode: "day"
    property int navOffset: 0
    property string dateLabel: ""
    property string rangeLabel: ""
    property string totalLabel: ""

    signal back()
    signal forward()
    signal weekToggled()

    height: 26

    // Left: title + day/week navigation.
    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Components.ThemedText {
            text: ""
            color: Helpers.Colors.accent
            font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }

        // ◀ go back in time (always available)
        Components.ThemedText {
            text: ""
            width: 26
            height: 24
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: navBackHover.hovered ? Helpers.Colors.accent : Helpers.Colors.textMuted
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            HoverHandler { id: navBackHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.back() }
        }

        Components.ThemedText {
            // Fixed width keeps the ▶ arrow from shifting as the
            // label changes ("Today" → "Yesterday" → "May 23 – 29").
            width: 132
            text: root.viewMode === "week" ? root.rangeLabel : root.dateLabel
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        // ▶ go forward (disabled at the live edge)
        Components.ThemedText {
            text: ""
            width: 26
            height: 24
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            opacity: root.navOffset > 0 ? 1 : 0.25
            color: navFwdHover.hovered && root.navOffset > 0 ? Helpers.Colors.accent : Helpers.Colors.textMuted
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            HoverHandler { id: navFwdHover; enabled: root.navOffset > 0; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: root.navOffset > 0; onTapped: root.forward() }
        }
    }

    // Right: total + day/week toggle.
    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Components.ThemedText {
            text: root.totalLabel
            muted: true
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }

        Components.ToggleChip {
            label: "7 days"
            active: root.viewMode === "week"
            anchors.verticalCenter: parent.verticalCenter
            onToggled: root.weekToggled()
        }
    }
}
