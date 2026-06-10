import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Top section: current conditions — big icon + temperature, weather details,
// environment grid and the air-quality summary, plus live HA sensor readings.
// `popup` is the weather Popup root: data + color/format helpers + actions.
Column {
    id: root

    property var popup: null

    spacing: 8

    // Header row: icon + temp + desc | details | AQI
    Row {
        spacing: 24
        anchors.horizontalCenter: parent.horizontalCenter

        // Left: big icon + temp
        Row {
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter

            Components.ThemedText {
                text: popup.dataLoaded ? popup.weatherIcon(popup.weatherCode, popup.isDay) : "󰖐"
                color: popup.dataLoaded ? popup.tempColor(popup.temperature) : Helpers.Colors.textMuted
                font.pixelSize: AppConfig.Config.theme.fontSizeDisplay
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter

                Components.ThemedText {
                    text: popup.dataLoaded ? Math.round(popup.temperature) + "°C" : "--"
                    color: popup.dataLoaded ? popup.tempColor(popup.temperature) : Helpers.Colors.textMuted
                    font.pixelSize: AppConfig.Config.theme.fontSizeHero
                    font.bold: true
                }

                Components.ThemedText {
                    text: popup.dataLoaded ? popup.weatherDesc(popup.weatherCode) : ""
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.fontSizeDefault
                }
                Row {
                    spacing: 6
                    Components.ThemedText {
                        visible: popup.cityName !== ""
                        text: popup.cityName + "  " + popup.latitude.toFixed(2) + ", " + popup.longitude.toFixed(2)
                        color: Qt.rgba(1, 1, 1, 0.3)
                        font.pixelSize: 9
                    }
                    Components.ThemedText {
                        text: "·  " + popup.lastFetchAgo
                        color: Qt.rgba(1, 1, 1, 0.3)
                        font.pixelSize: 9
                    }
                    Components.ThemedText {
                        text: "󰑐"
                        color: refreshArea.containsMouse ? Helpers.Colors.textDefault : Qt.rgba(1, 1, 1, 0.3)
                        font.pixelSize: 10
                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { popup.refreshAll(); popup.updateAgo(); }
                        }
                    }
                }

                // Live HA sensor readings
                Row {
                    visible: popup.haLiveLoaded
                    spacing: 10
                    Repeater {
                        model: popup.haLive
                        Row {
                            spacing: 4
                            Components.ThemedText {
                                text: modelData.label + ":"
                                color: modelData.color
                                font.pixelSize: 10
                            }
                            Components.ThemedText {
                                text: modelData.temp.toFixed(1) + "°"
                                color: popup.tempColor(modelData.temp)
                                font.pixelSize: 10
                            }
                            Components.ThemedText {
                                visible: modelData.humidity >= 0
                                text: Math.round(modelData.humidity) + "%"
                                muted: true
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }

        // Separator
        Rectangle { width: 1; height: 50; color: Qt.rgba(1, 1, 1, 0.1); anchors.verticalCenter: parent.verticalCenter }

        // Middle: weather details
        Grid {
            columns: 2
            columnSpacing: 6
            rowSpacing: 1
            anchors.verticalCenter: parent.verticalCenter

            Components.ThemedText { text: "Feels"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.feelsLike) + "°" : "--"; color: popup.dataLoaded ? popup.tempColor(popup.feelsLike) : Helpers.Colors.textMuted; font.pixelSize: 11 }
            Components.ThemedText { text: "Humid"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? popup.humidity + "%" : "--"; font.pixelSize: 11 }
            Components.ThemedText { text: "Wind"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.windSpeed) + " " + popup.windCardinal(popup.windDir) : "--"; font.pixelSize: 11 }
            Components.ThemedText { text: "Gusts"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.windGusts) + " km/h" : "--"; font.pixelSize: 11 }
        }

        // Separator
        Rectangle { width: 1; height: 50; color: Qt.rgba(1, 1, 1, 0.1); anchors.verticalCenter: parent.verticalCenter }

        // Middle-right: environment
        Grid {
            columns: 2
            columnSpacing: 6
            rowSpacing: 1
            anchors.verticalCenter: parent.verticalCenter

            Components.ThemedText { text: "Precip"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? popup.dailyPrecipSum.toFixed(1) + " mm " + popup.dailyPrecipProb + "%" : "--"; color: popup.dailyPrecipProb > 50 ? "#64b5f6" : Helpers.Colors.textDefault; font.pixelSize: 11 }
            Components.ThemedText { text: "Max wind"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.dailyWindMax) + " km/h" : "--"; color: popup.dailyWindMax > 50 ? "#ff9800" : Helpers.Colors.textDefault; font.pixelSize: 11 }
            Components.ThemedText { text: "Clouds"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? popup.cloudCover + "%" : "--"; font.pixelSize: 11 }
            Components.ThemedText { text: "UV"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? popup.uvIndex.toFixed(1) : "--"; color: popup.dataLoaded ? popup.uvColor(popup.uvIndex) : Helpers.Colors.textMuted; font.pixelSize: 11 }
            Components.ThemedText { text: "Pressure"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.pressure) + " hPa" : "--"; font.pixelSize: 11 }
            Components.ThemedText { text: "󰖜 / 󰖛"; muted: true; font.pixelSize: 11 }
            Components.ThemedText { text: popup.formatTime(popup.sunrise) + " / " + popup.formatTime(popup.sunset); font.pixelSize: 11 }
        }

        // Separator
        Rectangle { width: 1; height: 50; color: Qt.rgba(1, 1, 1, 0.1); anchors.verticalCenter: parent.verticalCenter }

        // Right: AQI
        Column {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter

            Components.ThemedText {
                text: popup.aqLoaded ? popup.euAqi : "--"
                color: popup.aqLoaded ? popup.aqiColor(popup.euAqi) : Helpers.Colors.textMuted
                font.pixelSize: AppConfig.Config.theme.fontSizeTitleLarge
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Components.ThemedText {
                text: popup.aqLoaded ? popup.aqiLabel(popup.euAqi) : ""
                color: popup.aqLoaded ? popup.aqiColor(popup.euAqi) : Helpers.Colors.textMuted
                font.pixelSize: 10
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Row {
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                Components.ThemedText { text: "PM2.5"; muted: true; font.pixelSize: 9 }
                Components.ThemedText { text: popup.aqLoaded ? popup.pm25.toFixed(0) : "--"; font.pixelSize: 9 }
            }
            Row {
                spacing: 8
                anchors.horizontalCenter: parent.horizontalCenter
                Components.ThemedText { text: "PM10"; muted: true; font.pixelSize: 9 }
                Components.ThemedText { text: popup.aqLoaded ? popup.pm10.toFixed(0) : "--"; font.pixelSize: 9 }
            }
        }
    }
}
