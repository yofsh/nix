import QtQuick
import "../../components" as Components
import "../../config" as AppConfig

// Section sub-header (icon + label) used inside cards.
Row {
    property int iconCode: 0
    property color iconColor: "#90caf9"
    property string label: ""

    spacing: 6

    Components.ThemedText {
        anchors.verticalCenter: parent.verticalCenter
        text: iconCode > 0 ? String.fromCodePoint(iconCode) : ""
        color: iconColor
        font.pixelSize: 13
    }
    Components.ThemedText {
        anchors.verticalCenter: parent.verticalCenter
        text: label
        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
        font.bold: true
    }
}
