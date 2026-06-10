import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// The standard popup button: subtle idle fill, accent highlight on hover,
// pointer cursor. Replaces the hand-rolled Rectangle+MouseArea pattern.
//
//   Components.ActionButton { label: "Start"; onClicked: root.startFocus(1500) }
//
// Disable via the inherited `enabled` (dims to 40%). Size is implicit from the
// label; set width/height explicitly for fixed layouts.
Rectangle {
    id: root

    property string label: ""
    property color highlight: Helpers.Colors.accent
    property int fontSize: AppConfig.Config.theme.popupFontSizeBody
    property bool bold: true
    readonly property bool hovered: mouseArea.containsMouse

    signal clicked()

    implicitWidth: buttonText.implicitWidth + 20
    implicitHeight: 28
    radius: 6
    opacity: enabled ? 1 : 0.4
    color: hovered ? Qt.rgba(highlight.r, highlight.g, highlight.b, 0.30) : Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: hovered ? highlight : "transparent"

    ThemedText {
        id: buttonText
        anchors.centerIn: parent
        text: root.label
        color: root.hovered ? root.highlight : Helpers.Colors.textDefault
        font.pixelSize: root.fontSize
        font.bold: root.bold
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
