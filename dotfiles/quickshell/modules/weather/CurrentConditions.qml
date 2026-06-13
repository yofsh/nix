import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Top section: current conditions — big hero (icon + temperature + description
// + live HA sensors), three detail grids (atmosphere / wind & sun / today),
// and the air-quality summary with pollen.
// `popup` is the weather Popup root: data + color/format helpers + actions.
Row {
    id: root

    property var popup: null
    readonly property int statSize: 12
    readonly property color sepColor: Qt.rgba(1, 1, 1, 0.1)
    readonly property int sepHeight: 96

    spacing: 46

    // ── Hero: big icon + temperature + description + sensors ──
    Row {
        spacing: 14
        anchors.verticalCenter: parent.verticalCenter

        Components.ThemedText {
            text: popup.dataLoaded ? popup.weatherIcon(popup.weatherCode, popup.isDay) : "󰖐"
            color: popup.dataLoaded ? popup.tempColor(popup.temperature) : Helpers.Colors.textMuted
            font.pixelSize: 54
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            spacing: 3
            anchors.verticalCenter: parent.verticalCenter

            Row {
                spacing: 12

                Components.ThemedText {
                    text: popup.dataLoaded ? Math.round(popup.temperature) + "°" : "--"
                    color: popup.dataLoaded ? popup.tempColor(popup.temperature) : Helpers.Colors.textMuted
                    font.pixelSize: 44
                    font.bold: true
                }

                Column {
                    spacing: 0
                    anchors.verticalCenter: parent.verticalCenter

                    Components.ThemedText {
                        text: popup.dataLoaded ? popup.weatherDesc(popup.weatherCode) : ""
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                    }
                    Components.ThemedText {
                        text: popup.dataLoaded ? "Feels like " + Math.round(popup.feelsLike) + "°" : ""
                        color: popup.dataLoaded ? popup.tempColor(popup.feelsLike) : Helpers.Colors.textMuted
                        font.pixelSize: root.statSize
                    }
                }
            }

            // Live HA sensor readings
            Row {
                visible: popup.haLiveLoaded
                spacing: 12
                Repeater {
                    model: popup.haLive
                    Row {
                        spacing: 5
                        Components.ThemedText {
                            text: modelData.label
                            color: modelData.color
                            font.pixelSize: root.statSize
                        }
                        Components.ThemedText {
                            text: modelData.temp.toFixed(1) + "°"
                            color: popup.tempColor(modelData.temp)
                            font.pixelSize: root.statSize
                            font.bold: true
                        }
                        Components.ThemedText {
                            visible: modelData.humidity >= 0
                            text: Math.round(modelData.humidity) + "%"
                            muted: true
                            font.pixelSize: root.statSize
                        }
                    }
                }
            }

            Row {
                spacing: 6
                Components.ThemedText {
                    visible: popup.cityName !== ""
                    text: "󰍎 " + popup.cityName + "  " + popup.latitude.toFixed(2) + ", " + popup.longitude.toFixed(2)
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
        }
    }

    Rectangle { width: 1; height: root.sepHeight; color: root.sepColor; anchors.verticalCenter: parent.verticalCenter }

    // ── Atmosphere ──
    Grid {
        columns: 2
        columnSpacing: 10
        rowSpacing: 3
        anchors.verticalCenter: parent.verticalCenter

        Components.ThemedText { text: "󰖎 Humidity"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? popup.humidity + "%" : "--"; color: popup.humidityColor(popup.humidity); font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰔏 Dew point"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.dewPoint) + "°" : "--"; color: popup.dewPointColor(popup.dewPoint); font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰊚 Pressure"; muted: true; font.pixelSize: root.statSize }
        Row {
            spacing: 4
            Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.pressure) + " hPa" : "--"; color: popup.pressureColor(popup.pressure); font.pixelSize: root.statSize }
            Components.ThemedText { text: popup.pressureTrend; color: popup.pressureTrendColor; font.pixelSize: root.statSize; font.bold: true }
        }
        Components.ThemedText { text: "󰖐 Clouds"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? popup.cloudCover + "%" : "--"; color: popup.cloudCover >= 85 ? Helpers.Colors.textMuted : Helpers.Colors.textDefault; font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰈈 Visibility"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? (popup.visibilityKm >= 10 ? Math.round(popup.visibilityKm) : popup.visibilityKm.toFixed(1)) + " km" : "--"; color: popup.visibilityColor(popup.visibilityKm); font.pixelSize: root.statSize }
    }

    Rectangle { width: 1; height: root.sepHeight; color: root.sepColor; anchors.verticalCenter: parent.verticalCenter }

    // ── Wind & sun ──
    Grid {
        columns: 2
        columnSpacing: 10
        rowSpacing: 3
        anchors.verticalCenter: parent.verticalCenter

        Components.ThemedText { text: "󰖝 Wind"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.windSpeed) + " km/h " + popup.windCardinal(popup.windDir) + " " + popup.windArrow(popup.windDir) : "--"; color: popup.windColor(popup.windSpeed); font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰖞 Gusts"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.windGusts) + " km/h" : "--"; color: popup.windColor(popup.windGusts); font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰓅 Max today"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? Math.round(popup.dailyWindMax) + " km/h" : "--"; color: popup.windColor(popup.dailyWindMax); font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰖨 UV"; muted: true; font.pixelSize: root.statSize }
        Row {
            spacing: 4
            Components.ThemedText { text: popup.dataLoaded ? popup.uvNow.toFixed(1) : "--"; color: popup.dataLoaded ? popup.uvColor(popup.uvNow) : Helpers.Colors.textMuted; font.pixelSize: root.statSize }
            Components.ThemedText { text: popup.dataLoaded ? "max " + popup.uvIndex.toFixed(1) : ""; color: popup.uvColor(popup.uvIndex); font.pixelSize: root.statSize; opacity: 0.7 }
        }
        Components.ThemedText { text: "󰖜 / 󰖛"; muted: true; font.pixelSize: root.statSize }
        Row {
            spacing: 5
            Components.ThemedText { text: popup.formatTime(popup.sunrise); font.pixelSize: root.statSize }
            Components.ThemedText { text: popup.sunriseCountdown; color: "#ffb74d"; font.pixelSize: root.statSize }
            Components.ThemedText { text: "/"; muted: true; font.pixelSize: root.statSize }
            Components.ThemedText { text: popup.formatTime(popup.sunset); font.pixelSize: root.statSize }
            Components.ThemedText { text: popup.sunsetCountdown; color: "#ce93d8"; font.pixelSize: root.statSize }
        }
    }

    Rectangle { width: 1; height: root.sepHeight; color: root.sepColor; anchors.verticalCenter: parent.verticalCenter }

    // ── Today: precipitation & daylight ──
    Grid {
        columns: 2
        columnSpacing: 10
        rowSpacing: 3
        anchors.verticalCenter: parent.verticalCenter

        Components.ThemedText { text: "󰖗 Precip"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? popup.dailyPrecipSum.toFixed(1) + " mm · " + popup.dailyPrecipProb + "%" : "--"; color: popup.dailyPrecipProb > 50 || popup.dailyPrecipSum >= 1 ? "#64b5f6" : Helpers.Colors.textDefault; font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰖖 Next rain"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? popup.nextRainLabel : "--"; color: popup.rainSoon ? "#64b5f6" : Helpers.Colors.textDefault; font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰖙 Sunshine"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? popup.fmtDuration(popup.sunshineSecs) : "--"; color: popup.sunshineColor(popup.sunshineSecs, popup.daylightSecs); font.pixelSize: root.statSize }
        Components.ThemedText { text: "󰥔 Daylight"; muted: true; font.pixelSize: root.statSize }
        Components.ThemedText { text: popup.dataLoaded ? popup.fmtDuration(popup.daylightSecs) : "--"; font.pixelSize: root.statSize }
    }

    Rectangle { width: 1; height: root.sepHeight; color: root.sepColor; anchors.verticalCenter: parent.verticalCenter }

    // ── Air quality + pollen ──
    Column {
        spacing: 2
        anchors.verticalCenter: parent.verticalCenter

        Components.ThemedText {
            text: popup.aqLoaded ? popup.euAqi : "--"
            color: popup.aqLoaded ? popup.aqiColor(popup.euAqi) : Helpers.Colors.textMuted
            font.pixelSize: AppConfig.Config.theme.fontSizeHero
            font.bold: true
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Components.ThemedText {
            text: popup.aqLoaded ? popup.aqiLabel(popup.euAqi) : ""
            color: popup.aqLoaded ? popup.aqiColor(popup.euAqi) : Helpers.Colors.textMuted
            font.pixelSize: 11
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Grid {
            columns: 4
            columnSpacing: 5
            rowSpacing: 1
            anchors.horizontalCenter: parent.horizontalCenter
            Components.ThemedText { text: "PM2.5"; muted: true; font.pixelSize: 10 }
            Components.ThemedText { text: popup.aqLoaded ? popup.pm25.toFixed(0) : "--"; color: popup.pollutantColor("pm25", popup.pm25); font.pixelSize: 10 }
            Components.ThemedText { text: "PM10"; muted: true; font.pixelSize: 10 }
            Components.ThemedText { text: popup.aqLoaded ? popup.pm10.toFixed(0) : "--"; color: popup.pollutantColor("pm10", popup.pm10); font.pixelSize: 10 }
            Components.ThemedText { text: "O₃"; muted: true; font.pixelSize: 10 }
            Components.ThemedText { text: popup.aqLoaded ? popup.o3.toFixed(0) : "--"; color: popup.pollutantColor("o3", popup.o3); font.pixelSize: 10 }
            Components.ThemedText { text: "NO₂"; muted: true; font.pixelSize: 10 }
            Components.ThemedText { text: popup.aqLoaded ? popup.no2.toFixed(0) : "--"; color: popup.pollutantColor("no2", popup.no2); font.pixelSize: 10 }
        }
        Row {
            visible: popup.pollen.length > 0
            spacing: 8
            anchors.horizontalCenter: parent.horizontalCenter
            Components.ThemedText { text: "󰳗"; muted: true; font.pixelSize: 10 }
            Repeater {
                model: popup.pollen
                Components.ThemedText {
                    text: modelData.name + " " + Math.round(modelData.val)
                    color: popup.pollenColor(modelData.val)
                    font.pixelSize: 10
                }
            }
        }
    }
}
