import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components

// Day header strip above the forecast chart: per-day icon, name, high/low,
// precipitation sum and max wind. One equal-width cell per forecast day.
// `popup` is the weather Popup root: dailyData + icon/color/format helpers.
Row {
    id: root

    property var popup: null

    Repeater {
        model: popup.dailyData
        Item {
            width: root.width / Math.max(popup.dailyData.length, 1)
            height: parent.height

            Column {
                anchors.centerIn: parent
                spacing: 1

                // Line 1: icon, day, high/low
                Row {
                    spacing: 4
                    anchors.horizontalCenter: parent.horizontalCenter

                    Components.ThemedText {
                        text: popup.weatherIcon(modelData.code, true)
                        font.pixelSize: 16
                    }
                    Components.ThemedText {
                        property string dn: popup.dayName(modelData.date)
                        text: dn
                        color: dn === "Today" ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                        font.pixelSize: 14
                        font.bold: dn === "Today"
                    }
                    Components.ThemedText {
                        text: modelData.high + "°"
                        color: popup.tempColor(modelData.high)
                        font.pixelSize: 14
                        font.bold: true
                    }
                    Components.ThemedText {
                        text: modelData.low + "°"
                        muted: true
                        font.pixelSize: 14
                    }
                }

                // Line 2: precipitation
                Components.ThemedText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰖗 " + modelData.precip.toFixed(1) + " mm"
                    color: modelData.precip > 0 ? "#64b5f6" : Helpers.Colors.textMuted
                    font.pixelSize: 12
                }

                // Line 3: wind
                Components.ThemedText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰖝 " + modelData.windMax + " km/h " + popup.windArrow(modelData.windDir)
                    color: modelData.windMax > 50 ? "#ff9800" : Helpers.Colors.textMuted
                    font.pixelSize: 12
                }
            }
        }
    }
}
