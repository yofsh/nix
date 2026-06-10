import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Week mode: daily average plus seven category-segmented day bars.
Column {
    id: root

    // weekMax is assigned in Popup.parseData *before* weekDays so the bar
    // delegates never read a stale max on first build (bind-before-build).
    property int weekMax: 1
    property var weekDays: []
    property string avgLabel: ""
    property var fmtTime: null   // shared formatTime(seconds) from the popup

    spacing: 10

    Row {
        width: parent.width
        spacing: 8
        Components.ThemedText {
            text: "Daily avg"
            muted: true
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }
        Components.ThemedText {
            text: root.avgLabel
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        id: weekBars
        width: parent.width
        height: 110
        readonly property real gap: 8
        readonly property real colW: (width - gap * 6) / 7

        Repeater {
            model: root.weekDays
            delegate: Column {
                required property var modelData
                required property int index
                width: weekBars.colW
                height: weekBars.height
                spacing: 4
                x: index * (weekBars.colW + weekBars.gap)

                Components.ThemedText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.seconds > 0 ? root.fmtTime(modelData.seconds) : ""
                    color: Qt.rgba(1, 1, 1, 0.5)
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                }

                // Category-segmented bar. Total height ∝ the
                // day's total vs. the week's busiest day; each
                // segment is a category, largest at the bottom
                // (backend sorts cats ascending). No grow
                // animation — bars appear at final size.
                Item {
                    id: barArea
                    width: parent.width
                    height: parent.height - 36

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.62
                        height: barArea.height * ((modelData.seconds || 0) / root.weekMax)
                        radius: 4
                        clip: true
                        color: modelData.seconds > 0 ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                        Column {
                            anchors.fill: parent
                            Repeater {
                                model: modelData.cats || []
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width
                                    height: barArea.height * ((modelData.seconds || 0) / root.weekMax)
                                    color: modelData.color || "#585b70"
                                }
                            }
                        }
                    }
                }

                Components.ThemedText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.label || ""
                    color: modelData.today ? Helpers.Colors.accent : Helpers.Colors.textMuted
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                    font.bold: modelData.today
                }
            }
        }
    }
}
