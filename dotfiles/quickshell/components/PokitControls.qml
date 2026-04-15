import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

Item {
    id: root
    implicitHeight: layoutCol.implicitHeight

    property var service: null

    // Mode values must match dokit CLI exactly (case-insensitive but space-separated)
    readonly property var modes: [
        { value: "DC Voltage",  short: "DCV" },
        { value: "AC Voltage",  short: "ACV" },
        { value: "DC Current",  short: "DCA" },
        { value: "AC Current",  short: "ACA" },
        { value: "Resistance",  short: "Ω" },
        { value: "Continuity",  short: "⏱" },
        { value: "Diode",       short: "▷|" },
        { value: "Temperature", short: "°C" }
    ]

    readonly property var rangesByMode: ({
        "DC Voltage":  ["auto", "300mV", "2V", "6V", "12V", "30V", "60V", "125V", "400V", "600V"],
        "AC Voltage":  ["auto", "300mV", "2V", "6V", "12V", "30V", "60V", "125V", "400V", "600V"],
        "DC Current":  ["auto", "500uA", "2mA", "10mA", "150mA", "300mA", "1A", "3A", "10A"],
        "AC Current":  ["auto", "500uA", "2mA", "10mA", "150mA", "300mA", "1A", "3A", "10A"],
        "Resistance":  ["auto", "30Ω", "75Ω", "400Ω", "5kΩ", "10kΩ", "100kΩ", "470kΩ", "1MΩ", "3MΩ"],
        "Continuity":  ["auto"],
        "Diode":       ["auto"],
        "Temperature": ["auto"]
    })

    Column {
        id: layoutCol
        width: parent.width
        spacing: AppConfig.Config.theme.spacingMedium

        // Mode row
        Flow {
            width: parent.width
            spacing: AppConfig.Config.theme.spacingSmall
            Repeater {
                model: root.modes
                Rectangle {
                    required property var modelData
                    width: modeText.implicitWidth + 14
                    height: 22
                    radius: AppConfig.Config.theme.cardRadiusSmall
                    color: root.service && root.service.currentMode === modelData.value
                           ? Qt.rgba(0.97, 0.89, 0.69, 0.18)
                           : Qt.rgba(1, 1, 1, 0.04)
                    border.color: root.service && root.service.currentMode === modelData.value
                                  ? Helpers.Colors.multimeter
                                  : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    Text {
                        id: modeText
                        anchors.centerIn: parent
                        text: modelData.short
                        color: root.service && root.service.currentMode === modelData.value
                               ? Helpers.Colors.multimeter
                               : Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeBody
                        font.bold: root.service && root.service.currentMode === modelData.value
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service) root.service.setMode(modelData.value)
                    }
                }
            }
        }

        // Range row
        Flow {
            width: parent.width
            spacing: AppConfig.Config.theme.spacingSmall
            Repeater {
                model: root.service ? (root.rangesByMode[root.service.currentMode] || ["Auto"]) : []
                Rectangle {
                    required property var modelData
                    width: rangeText.implicitWidth + 12
                    height: 20
                    radius: AppConfig.Config.theme.cardRadiusSmall
                    color: root.service && root.service.currentRange === modelData
                           ? Qt.rgba(0.65, 0.89, 0.63, 0.16)
                           : Qt.rgba(1, 1, 1, 0.04)
                    border.color: root.service && root.service.currentRange === modelData
                                  ? Helpers.Colors.multimeterActive
                                  : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    Text {
                        id: rangeText
                        anchors.centerIn: parent
                        text: modelData
                        color: root.service && root.service.currentRange === modelData
                               ? Helpers.Colors.multimeterActive
                               : Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.service) root.service.setRange(modelData)
                    }
                }
            }
        }
    }
}
