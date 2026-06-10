import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Icon / label / value line, anchored for alignment.
// Columns:  [14 icon] 4 [64 label] 4 [value ...]   ->  value starts at x=86
Item {
    property int iconCode: 0
    property color iconColor: Helpers.Colors.textMuted
    property string label: ""
    property string value: ""
    property bool valueMono: false
    property bool valueBold: false
    property color valueColor: Helpers.Colors.textDefault
    property string valueExtra: ""
    property color valueExtraColor: Helpers.Colors.textMuted

    width: parent ? parent.width : 0
    height: 14

    Components.ThemedText {
        id: _icon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        text: iconCode > 0 ? String.fromCodePoint(iconCode) : ""
        color: iconColor
        horizontalAlignment: Text.AlignHCenter
    }
    Components.ThemedText {
        id: _label
        anchors.left: _icon.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 64
        text: label
        muted: true
        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
        elide: Text.ElideRight
    }
    Components.ThemedText {
        id: _value
        anchors.left: _label.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: value
        color: valueColor
        font.family: valueMono ? "DejaVuSansM Nerd Font Mono" : AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
        font.bold: valueBold
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width - 86)
    }
    Components.ThemedText {
        anchors.left: _value.right
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: valueExtra
        color: valueExtraColor
        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
        visible: text.length > 0
        elide: Text.ElideRight
        width: Math.max(0, parent.width - 86 - _value.width - 4)
    }
}
