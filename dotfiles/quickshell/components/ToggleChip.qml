import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// Pill-shaped state chip ("7 days", "windows", pin toggles): accent-tinted when
// active, neutral when not. Emits toggled() on tap — the owner flips its state.
//
//   Components.ToggleChip { label: "7 days"; active: root.viewMode === "week"; onToggled: root.toggleWeek() }
Rectangle {
    id: root

    property string label: ""
    property bool active: false
    property int fontSize: AppConfig.Config.theme.popupFontSizeXSmall

    signal toggled()

    implicitWidth: chipText.implicitWidth + 16
    implicitHeight: 20
    radius: height / 2
    color: active ? Qt.rgba(Helpers.Colors.accent.r, Helpers.Colors.accent.g, Helpers.Colors.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: active ? Helpers.Colors.accent : Qt.rgba(1, 1, 1, 0.12)

    ThemedText {
        id: chipText
        anchors.centerIn: parent
        text: root.label
        color: root.active ? Helpers.Colors.accent : Helpers.Colors.textMuted
        font.pixelSize: root.fontSize
        font.bold: root.active
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: root.toggled()
    }
}
