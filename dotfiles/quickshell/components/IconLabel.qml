import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// Bar-widget icon + label pair with themed fonts. Either part hides when empty.
//
//   Components.IconLabel { icon: "󰖩"; label: root.ssid; iconColor: root.stateColor }
Row {
    id: root

    property string icon: ""
    property string label: ""
    property color iconColor: Helpers.Colors.textDefault
    property color labelColor: Helpers.Colors.textDefault
    property int iconSize: AppConfig.Config.theme.fontSizeIcon
    property int labelSize: AppConfig.Config.theme.fontSizeDefault
    property bool boldLabel: false

    spacing: AppConfig.Config.theme.spacingCompact

    Text {
        visible: root.icon !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.icon
        color: root.iconColor
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: root.iconSize
    }

    Text {
        visible: root.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.labelColor
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: root.labelSize
        font.bold: root.boldLabel
    }
}
