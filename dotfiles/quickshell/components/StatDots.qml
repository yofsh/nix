import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// A dot-separated row of stat strings with uniform padding. Each value is
// flanked by an evenly-spaced "·" separator (none before the first), so the
// gaps stay consistent instead of the ragged look of one concatenated string.
Row {
    id: root

    property var values: []                                       // array of strings
    property int fontSize: AppConfig.Config.theme.popupFontSizeSmall
    property color valueColor: Helpers.Colors.textMuted
    property color firstColor: Helpers.Colors.textDefault
    property bool boldFirst: false                                // emphasize values[0]

    spacing: 8

    Repeater {
        model: root.values
        delegate: Row {
            required property var modelData
            required property int index
            spacing: 8

            Text {
                visible: index > 0                                // positioners skip invisible items — no leading gap
                text: "·"
                color: Qt.rgba(1, 1, 1, 0.25)
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: root.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: modelData
                color: (root.boldFirst && index === 0) ? root.firstColor : root.valueColor
                font.bold: root.boldFirst && index === 0
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: root.fontSize
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
