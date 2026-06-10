import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// Popup title row: bold accent title on the left, optional trailing content
// (status text, chips, buttons) right-aligned. Children land in the trailing row.
//
//   Components.PopupHeader {
//       title: " Focus"
//       Components.ThemedText { muted: true; text: "ready" }
//   }
Item {
    id: root

    property string title: ""
    property color titleColor: Helpers.Colors.accent
    default property alias trailing: trailingRow.data

    width: parent ? parent.width : implicitWidth
    height: 22

    ThemedText {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        color: root.titleColor
        font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
        font.bold: true
    }

    Row {
        id: trailingRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: AppConfig.Config.theme.spacingDefault
    }
}
