import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: row.implicitWidth + 4
    implicitHeight: parent ? parent.height : 22

    property var context: null
    property bool hovered: false

    property real latitude: AppConfig.Config.weather.latitude
    property real longitude: AppConfig.Config.weather.longitude

    property real temperature: 0
    property int weatherCode: -1
    property bool isDay: true
    property bool dataLoaded: false

    property int euAqi: 0
    property bool aqLoaded: false

    function weatherIcon(code, day) {
        if (code === 0 || code === 1) return day ? "󰖙" : "󰖔";
        if (code === 2) return day ? "󰖕" : "󰼱";
        if (code === 3) return "󰖐";
        if (code === 45 || code === 48) return "󰖑";
        if (code >= 51 && code <= 57) return "󰖗";
        if (code >= 61 && code <= 67) return "󰖖";
        if (code >= 71 && code <= 77) return "󰖘";
        if (code >= 80 && code <= 82) return "󰖖";
        if (code >= 85 && code <= 86) return "󰖘";
        if (code >= 95) return "󰖓";
        return "󰖐";
    }

    function tempColor(t) {
        if (t <= 0) return "#64b5f6";
        if (t <= 10) return "#90caf9";
        if (t <= 25) return Helpers.Colors.textMuted;
        if (t <= 35) return "#ff9800";
        return "#f53c3c";
    }

    function aqiColor(aqi) {
        if (aqi <= 20) return "#4caf50";
        if (aqi <= 40) return "#8bc34a";
        if (aqi <= 60) return "#ff9800";
        if (aqi <= 80) return "#ff5722";
        if (aqi <= 100) return "#f53c3c";
        return "#9c27b0";
    }

    // Fetch weather
    Process {
        id: weatherProc
        command: ["curl", "-s", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude
            + "&longitude=" + root.longitude
            + "&current=temperature_2m,weather_code,is_day"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.current) {
                        root.temperature = data.current.temperature_2m;
                        root.weatherCode = data.current.weather_code;
                        root.isDay = data.current.is_day === 1;
                        root.dataLoaded = true;
                    }
                } catch (e) {}
            }
        }
    }

    // Fetch AQI
    Process {
        id: aqProc
        command: ["curl", "-s", "--max-time", "10",
            "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" + root.latitude
            + "&longitude=" + root.longitude
            + "&current=european_aqi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.current) {
                        root.euAqi = data.current.european_aqi || 0;
                        root.aqLoaded = true;
                    }
                } catch (e) {}
            }
        }
    }

    // Fast retry until first successful fetch (handles no-net at startup),
    // then settles into the configured refresh interval.
    Timer {
        interval: root.dataLoaded ? AppConfig.Config.weather.refreshInterval : 15000
        running: true
        repeat: true
        onTriggered: { weatherProc.running = true; aqProc.running = true; }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            text: root.dataLoaded ? root.weatherIcon(root.weatherCode, root.isDay) : "󰖐"
            color: root.dataLoaded ? root.tempColor(root.temperature) : Helpers.Colors.textMuted
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.dataLoaded ? Math.round(root.temperature) + "°" : "--"
            color: root.dataLoaded ? root.tempColor(root.temperature) : Helpers.Colors.textMuted
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.aqLoaded
            text: root.euAqi
            color: root.aqiColor(root.euAqi)
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: {
            if (root.context)
                root.context.togglePopup();
        }
        onEntered: root.hovered = true
        onExited: root.hovered = false
    }
}
