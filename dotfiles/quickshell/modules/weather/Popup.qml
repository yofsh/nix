import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

PanelWindow {
    id: root
    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false
    property real latitude: AppConfig.Config.weather.latitude
    property real longitude: AppConfig.Config.weather.longitude
    property string cityName: AppConfig.Config.weather.city

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: 1020
    implicitHeight: 380
    visible: popupOpen
    color: "transparent"

    // Current weather
    property real temperature: 0
    property real feelsLike: 0
    property int humidity: 0
    property int weatherCode: -1
    property real windSpeed: 0
    property real windGusts: 0
    property int windDir: 0
    property bool isDay: true
    property int cloudCover: 0
    property real pressure: 0
    property real precipitation: 0
    property bool dataLoaded: false

    // Daily (today)
    property string sunrise: ""
    property string sunset: ""
    property real uvIndex: 0
    property real dailyPrecipSum: 0
    property int dailyPrecipProb: 0
    property real dailyWindMax: 0

    // Air quality
    property int euAqi: 0
    property real pm25: 0
    property real pm10: 0
    property real no2: 0
    property real o3: 0
    property real so2: 0
    property real co: 0
    property bool aqLoaded: false

    // Hourly forecast (for graph)
    property var hourlyTime: []
    property var hourlyTemp: []
    property var hourlyPrecip: []
    property var hourlyWind: []
    property var hourlyCode: []
    property var dailyData: []  // [{date, code, high, low}]

    // HA sensor history: array of {label, color, times: [epoch_ms], temps: [float]}
    property var haSensors: []
    property bool haLoaded: false
    property int haPending: 0

    // HA live sensor readings
    property var haLive: []  // [{label, color, temp, humidity}]
    property bool haLiveLoaded: false

    // HA rain sensor history: [{start: epoch_ms, end: epoch_ms}]
    property var haRainEvents: []
    property bool haRainLoaded: false

    // Last fetch timestamp
    property real lastFetchTime: 0
    property string lastFetchAgo: "--"

    function refreshAll() {
        weatherProc.running = true;
        aqProc.running = true;
        haProc.running = true;
        haLiveProc.running = true;
        haRainProc.running = true;
        root.lastFetchTime = Date.now();
    }

    function updateAgo() {
        if (lastFetchTime <= 0) { lastFetchAgo = "--"; return; }
        var secs = Math.floor((Date.now() - lastFetchTime) / 1000);
        if (secs < 60) lastFetchAgo = secs + "s ago";
        else if (secs < 3600) lastFetchAgo = Math.floor(secs / 60) + "m ago";
        else lastFetchAgo = Math.floor(secs / 3600) + "h ago";
    }

    Timer {
        interval: 10000
        running: root.popupOpen
        repeat: true
        onTriggered: root.updateAgo()
    }

    // Hover state
    property real hoverX: -1
    property int hoverIdx: -1

    // Pre-fetch all data on startup — popup opens instantly
    Component.onCompleted: root.refreshAll()
    onPopupOpenChanged: if (popupOpen) root.updateAgo()

    // ── Helper functions ──

    function windCardinal(deg) {
        var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return dirs[Math.round(deg / 45) % 8];
    }

    // Wind arrows point in the direction wind is blowing TO (meteorological: from deg, arrow: +180)
    function windArrow(deg) {
        var arrows = ["↓", "↙", "←", "↖", "↑", "↗", "→", "↘"];
        return arrows[Math.round(deg / 45) % 8];
    }

    function weatherDesc(code) {
        if (code === 0) return "Clear sky";
        if (code === 1) return "Mainly clear";
        if (code === 2) return "Partly cloudy";
        if (code === 3) return "Overcast";
        if (code === 45) return "Fog";
        if (code === 48) return "Depositing rime fog";
        if (code === 51) return "Light drizzle";
        if (code === 53) return "Moderate drizzle";
        if (code === 55) return "Dense drizzle";
        if (code === 56) return "Light freezing drizzle";
        if (code === 57) return "Dense freezing drizzle";
        if (code === 61) return "Slight rain";
        if (code === 63) return "Moderate rain";
        if (code === 65) return "Heavy rain";
        if (code === 66) return "Light freezing rain";
        if (code === 67) return "Heavy freezing rain";
        if (code === 71) return "Slight snow";
        if (code === 73) return "Moderate snow";
        if (code === 75) return "Heavy snow";
        if (code === 77) return "Snow grains";
        if (code === 80) return "Slight rain showers";
        if (code === 81) return "Moderate rain showers";
        if (code === 82) return "Violent rain showers";
        if (code === 85) return "Slight snow showers";
        if (code === 86) return "Heavy snow showers";
        if (code === 95) return "Thunderstorm";
        if (code === 96) return "Thunderstorm with slight hail";
        if (code === 99) return "Thunderstorm with heavy hail";
        return "";
    }

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
        if (t <= 25) return Helpers.Colors.textDefault;
        if (t <= 35) return "#ff9800";
        return "#f53c3c";
    }

    function uvColor(uv) {
        if (uv <= 2) return "#4caf50";
        if (uv <= 5) return "#ff9800";
        if (uv <= 7) return "#ff5722";
        if (uv <= 10) return "#f53c3c";
        return "#9c27b0";
    }

    function aqiColor(aqi) {
        if (aqi <= 20) return "#4caf50";
        if (aqi <= 40) return "#8bc34a";
        if (aqi <= 60) return "#ff9800";
        if (aqi <= 80) return "#ff5722";
        if (aqi <= 100) return "#f53c3c";
        return "#9c27b0";
    }

    function aqiLabel(aqi) {
        if (aqi <= 20) return "Good";
        if (aqi <= 40) return "Fair";
        if (aqi <= 60) return "Moderate";
        if (aqi <= 80) return "Poor";
        if (aqi <= 100) return "Very poor";
        return "Hazardous";
    }

    function formatTime(iso) {
        if (!iso) return "--";
        var d = new Date(iso);
        var h = d.getHours();
        var m = d.getMinutes();
        return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m;
    }

    function dayName(dateStr) {
        var now = new Date();
        var today = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0");
        var tom = new Date(now);
        tom.setDate(tom.getDate() + 1);
        var tomorrow = tom.getFullYear() + "-" + String(tom.getMonth() + 1).padStart(2, "0") + "-" + String(tom.getDate()).padStart(2, "0");
        if (dateStr === today) return "Today";
        if (dateStr === tomorrow) return "Tomorrow";
        var d = new Date(dateStr);
        var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
        return days[d.getDay()];
    }

    // ── Data fetching ──


    Process {
        id: weatherProc
        command: ["curl", "-s", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude
            + "&longitude=" + root.longitude
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day,cloud_cover,surface_pressure,precipitation"
            + "&hourly=temperature_2m,precipitation,wind_speed_10m,weather_code"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,sunrise,sunset,uv_index_max"
            + "&timezone=auto&forecast_days=5&past_days=" + AppConfig.Config.weather.haHistoryDays]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.current) {
                        var c = data.current;
                        root.temperature = c.temperature_2m;
                        root.feelsLike = c.apparent_temperature;
                        root.humidity = c.relative_humidity_2m;
                        root.weatherCode = c.weather_code;
                        root.windSpeed = c.wind_speed_10m;
                        root.windGusts = c.wind_gusts_10m;
                        root.windDir = c.wind_direction_10m;
                        root.isDay = c.is_day === 1;
                        root.cloudCover = c.cloud_cover;
                        root.pressure = c.surface_pressure;
                        root.precipitation = c.precipitation;
                        root.dataLoaded = true;
                    }
                    if (data.hourly) {
                        root.hourlyTime = data.hourly.time;
                        root.hourlyTemp = data.hourly.temperature_2m;
                        root.hourlyPrecip = data.hourly.precipitation;
                        root.hourlyWind = data.hourly.wind_speed_10m;
                        root.hourlyCode = data.hourly.weather_code;
                    }
                    if (data.daily) {
                        var d = data.daily;
                        root.sunrise = d.sunrise[0] || "";
                        root.sunset = d.sunset[0] || "";
                        root.uvIndex = d.uv_index_max[0] || 0;
                        root.dailyPrecipSum = d.precipitation_sum[0] || 0;
                        root.dailyPrecipProb = d.precipitation_probability_max[0] || 0;
                        root.dailyWindMax = d.wind_speed_10m_max[0] || 0;
                        var days = [];
                        for (var i = 0; i < d.time.length; i++) {
                            days.push({
                                date: d.time[i],
                                code: d.weather_code[i],
                                high: Math.round(d.temperature_2m_max[i]),
                                low: Math.round(d.temperature_2m_min[i]),
                                precip: d.precipitation_sum[i] || 0,
                                precipProb: d.precipitation_probability_max[i] || 0,
                                windMax: Math.round(d.wind_speed_10m_max[i] || 0),
                                windDir: d.wind_direction_10m_dominant[i] || 0
                            });
                        }
                        root.dailyData = days;
                    }
                    graphCanvas.requestPaint();
                } catch (e) {}
            }
        }
    }

    Process {
        id: aqProc
        command: ["curl", "-s", "--max-time", "10",
            "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" + root.latitude
            + "&longitude=" + root.longitude
            + "&current=european_aqi,pm10,pm2_5,nitrogen_dioxide,ozone,sulphur_dioxide,carbon_monoxide"
            + "&timezone=auto"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (data.current) {
                        var c = data.current;
                        root.euAqi = c.european_aqi || 0;
                        root.pm25 = c.pm2_5 || 0;
                        root.pm10 = c.pm10 || 0;
                        root.no2 = c.nitrogen_dioxide || 0;
                        root.o3 = c.ozone || 0;
                        root.so2 = c.sulphur_dioxide || 0;
                        root.co = c.carbon_monoxide || 0;
                        root.aqLoaded = true;
                    }
                } catch (e) {}
            }
        }
    }

    // HA sensor history — fetch all configured sensors via one curl (comma-separated entity_ids)
    Process {
        id: haProc
        property string startTime: {
            var d = new Date();
            d.setDate(d.getDate() - AppConfig.Config.weather.haHistoryDays);
            d.setHours(0, 0, 0, 0);
            return d.toISOString();
        }
        property string entityIds: {
            var cfg = AppConfig.Config.weather.haSensors;
            var ids = [];
            for (var i = 0; i < cfg.length; i++) ids.push(cfg[i].entityId);
            return ids.join(",");
        }
        property string endTime: new Date().toISOString()
        command: ["curl", "-s", "--max-time", "15",
            "-H", "Authorization: Bearer " + AppConfig.Config.weather.haToken,
            AppConfig.Config.weather.haUrl + "/api/history/period/" + startTime
            + "?end_time=" + endTime
            + "&filter_entity_id=" + entityIds
            + "&significant_changes_only&minimal_response&no_attributes"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseHaHistory(this.text);
            }
        }
    }

    function parseHaHistory(rawText) {
        try {
            var data = JSON.parse(rawText);
            if (!data || data.length === 0) return;

            var cfg = AppConfig.Config.weather.haSensors;
            var sensors = [];

            for (var s = 0; s < data.length; s++) {
                var raw = data[s];
                if (!raw || raw.length === 0) continue;

                // Identify which sensor this is
                var eid = raw[0].entity_id || "";
                var meta = null;
                for (var m = 0; m < cfg.length; m++) {
                    if (cfg[m].entityId === eid) { meta = cfg[m]; break; }
                }
                if (!meta) continue;

                // Group by LOCAL hour
                var buckets = {};
                for (var i = 0; i < raw.length; i++) {
                    var val = parseFloat(raw[i].state);
                    if (isNaN(val)) continue;
                    var ts = raw[i].last_changed || raw[i].last_updated || "";
                    var d = new Date(ts);
                    if (isNaN(d.getTime())) continue;
                    var localHour = new Date(d.getFullYear(), d.getMonth(), d.getDate(), d.getHours());
                    var key = localHour.getTime();
                    if (!buckets[key]) buckets[key] = { sum: 0, count: 0 };
                    buckets[key].sum += val;
                    buckets[key].count++;
                }

                var keys = Object.keys(buckets).sort(function(a, b) { return a - b; });
                var times = [];
                var temps = [];
                for (var k = 0; k < keys.length; k++) {
                    var b = buckets[keys[k]];
                    times.push(parseInt(keys[k]));
                    temps.push(b.sum / b.count);
                }

                if (times.length > 0) {
                    sensors.push({ label: meta.label, color: meta.color, times: times, temps: temps });
                }
            }

            root.haSensors = sensors;
            root.haLoaded = sensors.length > 0;
            graphCanvas.requestPaint();
        } catch (e) {}
    }

    // HA live sensor states (temp + humidity)
    Process {
        id: haLiveProc
        property string entityIds: {
            var cfg = AppConfig.Config.weather.haSensors;
            var ids = [];
            for (var i = 0; i < cfg.length; i++) {
                var base = cfg[i].entityId.replace("_temperature", "");
                ids.push(cfg[i].entityId);
                ids.push(base + "_humidity");
            }
            return ids.join(",");
        }
        command: ["bash", "-c",
            "for e in " + entityIds.split(",").map(function(e) { return "'" + e + "'"; }).join(" ") + "; do "
            + "curl -s -H 'Authorization: Bearer " + AppConfig.Config.weather.haToken + "' "
            + "'" + AppConfig.Config.weather.haUrl + "/api/states/'\"$e\" | jq -c '{entity_id:.entity_id,state:.state}'; done"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var lines = this.text.trim().split("\n");
                    var states = {};
                    for (var i = 0; i < lines.length; i++) {
                        var obj = JSON.parse(lines[i]);
                        states[obj.entity_id] = obj.state;
                    }
                    var cfg = AppConfig.Config.weather.haSensors;
                    var live = [];
                    for (var s = 0; s < cfg.length; s++) {
                        var tempId = cfg[s].entityId;
                        var humId = tempId.replace("_temperature", "_humidity");
                        var temp = parseFloat(states[tempId]);
                        var hum = parseFloat(states[humId]);
                        if (!isNaN(temp)) {
                            live.push({
                                label: cfg[s].label,
                                color: cfg[s].color,
                                temp: temp,
                                humidity: isNaN(hum) ? -1 : hum
                            });
                        }
                    }
                    root.haLive = live;
                    root.haLiveLoaded = live.length > 0;
                } catch (e) {}
            }
        }
    }

    // HA rain sensor history
    Process {
        id: haRainProc
        property string startTime: {
            var d = new Date();
            d.setDate(d.getDate() - AppConfig.Config.weather.haHistoryDays);
            d.setHours(0, 0, 0, 0);
            return d.toISOString();
        }
        command: ["curl", "-s", "--max-time", "15",
            "-H", "Authorization: Bearer " + AppConfig.Config.weather.haToken,
            AppConfig.Config.weather.haUrl + "/api/history/period/" + startTime
            + "?end_time=" + new Date().toISOString()
            + "&filter_entity_id=" + AppConfig.Config.weather.haRainSensor
            + "&significant_changes_only&minimal_response&no_attributes"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var data = JSON.parse(this.text);
                    if (!data || !data[0] || data[0].length === 0) return;
                    var raw = data[0];

                    // Build rain event intervals
                    var events = [];
                    var rainStart = -1;
                    for (var i = 0; i < raw.length; i++) {
                        var state = raw[i].state;
                        var ts = raw[i].last_changed || raw[i].last_updated || "";
                        var epoch = new Date(ts).getTime();
                        if (isNaN(epoch)) continue;

                        if (state === "raining" && rainStart < 0) {
                            rainStart = epoch;
                        } else if (state !== "raining" && rainStart >= 0) {
                            events.push({ start: rainStart, end: epoch });
                            rainStart = -1;
                        }
                    }
                    // If still raining at end of data
                    if (rainStart >= 0) {
                        events.push({ start: rainStart, end: Date.now() });
                    }

                    root.haRainEvents = events;
                    root.haRainLoaded = events.length > 0;
                    graphCanvas.requestPaint();
                } catch (e) {}
            }
        }
    }

    // Background refresh — fast retry until first successful fetch (handles no-net at startup),
    // then settles into a 5 min cadence to keep popup data fresh.
    Timer {
        interval: (root.dataLoaded && root.hourlyTemp.length > 1) ? 300000 : 15000
        running: true
        repeat: true
        onTriggered: root.refreshAll()
    }

    // ── UI ──

    Item {
        anchors.fill: parent
        clip: true

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface {
                anchors.fill: parent
            }

            // ── Top section: current conditions + air quality ──
            Column {
                id: topSection
                anchors.top: parent.top
                anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                // Header row: icon + temp + desc | details | AQI
                Row {
                    spacing: 24
                    anchors.horizontalCenter: parent.horizontalCenter

                    // Left: big icon + temp
                    Row {
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: root.dataLoaded ? root.weatherIcon(root.weatherCode, root.isDay) : "󰖐"
                            color: root.dataLoaded ? root.tempColor(root.temperature) : Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeDisplay
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: root.dataLoaded ? Math.round(root.temperature) + "°C" : "--"
                                color: root.dataLoaded ? root.tempColor(root.temperature) : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeHero
                                font.bold: true
                            }

                            Text {
                                text: root.dataLoaded ? root.weatherDesc(root.weatherCode) : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeDefault
                            }
                            Row {
                                spacing: 6
                                Text {
                                    visible: root.cityName !== ""
                                    text: root.cityName + "  " + root.latitude.toFixed(2) + ", " + root.longitude.toFixed(2)
                                    color: Qt.rgba(1, 1, 1, 0.3)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: 9
                                }
                                Text {
                                    text: "·  " + root.lastFetchAgo
                                    color: Qt.rgba(1, 1, 1, 0.3)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: 9
                                }
                                Text {
                                    text: "󰑐"
                                    color: refreshArea.containsMouse ? Helpers.Colors.textDefault : Qt.rgba(1, 1, 1, 0.3)
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: 10
                                    MouseArea {
                                        id: refreshArea
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.refreshAll(); root.updateAgo(); }
                                    }
                                }
                            }

                            // Live HA sensor readings
                            Row {
                                visible: root.haLiveLoaded
                                spacing: 10
                                Repeater {
                                    model: root.haLive
                                    Row {
                                        spacing: 4
                                        Text {
                                            text: modelData.label + ":"
                                            color: modelData.color
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                        Text {
                                            text: modelData.temp.toFixed(1) + "°"
                                            color: root.tempColor(modelData.temp)
                                            font.family: AppConfig.Config.theme.fontFamily
                                            font.pixelSize: 10
                                        }
                                        Text {
                                            visible: modelData.humidity >= 0
                                            text: Math.round(modelData.humidity) + "%"
                                            color: Helpers.Colors.textMuted
                                            font.family: AppConfig.Config.theme.fontFamily
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

                        Text { text: "Feels"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? Math.round(root.feelsLike) + "°" : "--"; color: root.dataLoaded ? root.tempColor(root.feelsLike) : Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "Humid"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? root.humidity + "%" : "--"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "Wind"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? Math.round(root.windSpeed) + " " + root.windCardinal(root.windDir) : "--"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "Gusts"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? Math.round(root.windGusts) + " km/h" : "--"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                    }

                    // Separator
                    Rectangle { width: 1; height: 50; color: Qt.rgba(1, 1, 1, 0.1); anchors.verticalCenter: parent.verticalCenter }

                    // Middle-right: environment
                    Grid {
                        columns: 2
                        columnSpacing: 6
                        rowSpacing: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Text { text: "Precip"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? root.dailyPrecipSum.toFixed(1) + " mm " + root.dailyPrecipProb + "%" : "--"; color: root.dailyPrecipProb > 50 ? "#64b5f6" : Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "Max wind"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? Math.round(root.dailyWindMax) + " km/h" : "--"; color: root.dailyWindMax > 50 ? "#ff9800" : Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "Clouds"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? root.cloudCover + "%" : "--"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "UV"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? root.uvIndex.toFixed(1) : "--"; color: root.dataLoaded ? root.uvColor(root.uvIndex) : Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "Pressure"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.dataLoaded ? Math.round(root.pressure) + " hPa" : "--"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: "󰖜 / 󰖛"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                        Text { text: root.formatTime(root.sunrise) + " / " + root.formatTime(root.sunset); color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 11 }
                    }

                    // Separator
                    Rectangle { width: 1; height: 50; color: Qt.rgba(1, 1, 1, 0.1); anchors.verticalCenter: parent.verticalCenter }

                    // Right: AQI
                    Column {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: root.aqLoaded ? root.euAqi : "--"
                            color: root.aqLoaded ? root.aqiColor(root.euAqi) : Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeTitleLarge
                            font.bold: true
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: root.aqLoaded ? root.aqiLabel(root.euAqi) : ""
                            color: root.aqLoaded ? root.aqiColor(root.euAqi) : Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Row {
                            spacing: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            Text { text: "PM2.5"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 9 }
                            Text { text: root.aqLoaded ? root.pm25.toFixed(0) : "--"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 9 }
                        }
                        Row {
                            spacing: 8
                            anchors.horizontalCenter: parent.horizontalCenter
                            Text { text: "PM10"; color: Helpers.Colors.textMuted; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 9 }
                            Text { text: root.aqLoaded ? root.pm10.toFixed(0) : "--"; color: Helpers.Colors.textDefault; font.family: AppConfig.Config.theme.fontFamily; font.pixelSize: 9 }
                        }
                    }
                }
            }

            // ── Graph section: forecast ──
            Item {
                id: graphSection
                anchors.top: topSection.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6

                // Day header row with icons
                Row {
                    id: dayHeaderRow
                    anchors.top: parent.top
                    anchors.left: graphCanvas.left
                    anchors.right: graphCanvas.right
                    height: 66

                    Repeater {
                        model: root.dailyData
                        Item {
                            width: dayHeaderRow.width / Math.max(root.dailyData.length, 1)
                            height: parent.height

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                // Line 1: icon, day, high/low
                                Row {
                                    spacing: 4
                                    anchors.horizontalCenter: parent.horizontalCenter

                                    Text {
                                        text: root.weatherIcon(modelData.code, true)
                                        color: Helpers.Colors.textDefault
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: 16
                                    }
                                    Text {
                                        property string dn: root.dayName(modelData.date)
                                        text: dn
                                        color: dn === "Today" ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: 14
                                        font.bold: dn === "Today"
                                    }
                                    Text {
                                        text: modelData.high + "°"
                                        color: root.tempColor(modelData.high)
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: 14
                                        font.bold: true
                                    }
                                    Text {
                                        text: modelData.low + "°"
                                        color: Helpers.Colors.textMuted
                                        font.family: AppConfig.Config.theme.fontFamily
                                        font.pixelSize: 14
                                    }
                                }

                                // Line 2: precipitation
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰖗 " + modelData.precip.toFixed(1) + " mm"
                                    color: modelData.precip > 0 ? "#64b5f6" : Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: 12
                                }

                                // Line 3: wind
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "󰖝 " + modelData.windMax + " km/h " + root.windArrow(modelData.windDir)
                                    color: modelData.windMax > 50 ? "#ff9800" : Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }

                // Y-axis labels (temperature)
                Repeater {
                    model: root.yLabels
                    Text {
                        x: 4
                        y: graphCanvas.y + modelData.y - 5
                        text: modelData.label
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeTiny
                    }
                }

                // Legend
                Row {
                    visible: root.haLoaded || root.haRainLoaded
                    anchors.right: graphCanvas.right
                    anchors.top: dayHeaderRow.bottom
                    anchors.topMargin: 2
                    z: 1
                    spacing: 10

                    Repeater {
                        model: root.haSensors
                        Row {
                            spacing: 3
                            Rectangle { width: 12; height: 2; color: modelData.color; anchors.verticalCenter: parent.verticalCenter; border.width: 0; radius: 1 }
                            Text {
                                text: modelData.label
                                color: Qt.rgba(1, 1, 1, 0.4)
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: 8
                            }
                        }
                    }
                    Row {
                        visible: root.haRainLoaded
                        spacing: 3
                        Rectangle { width: 8; height: 8; color: Qt.rgba(0.3, 0.8, 0.3, 0.5); anchors.verticalCenter: parent.verticalCenter; border.width: 0; radius: 1 }
                        Text {
                            text: "Rain (sensor)"
                            color: Qt.rgba(1, 1, 1, 0.4)
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: 8
                        }
                    }
                }

                // Canvas graph
                Canvas {
                    id: graphCanvas
                    anchors.top: dayHeaderRow.bottom
                    anchors.left: parent.left
                    anchors.leftMargin: 32
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    height: parent.height - dayHeaderRow.height - 12

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);

                        var temps = root.hourlyTemp;
                        var precips = root.hourlyPrecip;
                        var winds = root.hourlyWind;
                        if (temps.length < 2) return;

                        var w = width;
                        var h = height;
                        var n = temps.length;

                        // Temperature range with padding
                        var tMin = temps[0], tMax = temps[0];
                        for (var i = 0; i < n; i++) {
                            if (temps[i] < tMin) tMin = temps[i];
                            if (temps[i] > tMax) tMax = temps[i];
                        }
                        tMin = Math.floor(tMin / 5) * 5 - 2;
                        tMax = Math.ceil(tMax / 5) * 5 + 2;
                        var tRange = tMax - tMin || 1;

                        // Precip max
                        var pMax = 0.5;
                        for (var ip = 0; ip < precips.length; ip++) {
                            if (precips[ip] > pMax) pMax = precips[ip];
                        }

                        // Wind max
                        var wMax = 10;
                        for (var iw = 0; iw < winds.length; iw++) {
                            if (winds[iw] > wMax) wMax = winds[iw];
                        }

                        // ── Grid lines ──
                        var gridStep = tRange <= 15 ? 5 : 10;
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.06);
                        ctx.lineWidth = 1;
                        for (var gt = Math.ceil(tMin / gridStep) * gridStep; gt <= tMax; gt += gridStep) {
                            var gy = h - ((gt - tMin) / tRange) * h;
                            ctx.beginPath();
                            ctx.moveTo(0, gy);
                            ctx.lineTo(w, gy);
                            ctx.stroke();
                        }

                        // ── Day boundary lines ──
                        var times = root.hourlyTime;
                        ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.12);
                        ctx.lineWidth = 1;
                        for (var id = 1; id < times.length; id++) {
                            if (times[id].indexOf("T00:00") !== -1) {
                                var dx = (id / n) * w;
                                ctx.beginPath();
                                ctx.moveTo(dx, 0);
                                ctx.lineTo(dx, h);
                                ctx.stroke();
                            }
                        }

                        // ── Precipitation bars ──
                        var barW = Math.max(2, w / n - 1);
                        var precipH = h * 0.3;  // bottom 30% for precip
                        for (var ip2 = 0; ip2 < precips.length; ip2++) {
                            if (precips[ip2] <= 0) continue;
                            var px = (ip2 / n) * w;
                            var pH = Math.min((precips[ip2] / pMax) * precipH, precipH);
                            ctx.fillStyle = Qt.rgba(0.39, 0.71, 0.96, 0.5);
                            ctx.fillRect(px, h - pH, barW, pH);
                        }

                        // ── HA rain sensor events (drawn over precip bars) ──
                        if (root.haRainLoaded) {
                            var forecastStartR = new Date(times[0]).getTime();
                            var forecastEndR = new Date(times[n - 1]).getTime();
                            var forecastSpanR = forecastEndR - forecastStartR || 1;

                            ctx.fillStyle = Qt.rgba(0.3, 0.8, 0.3, 0.7);
                            for (var ir = 0; ir < root.haRainEvents.length; ir++) {
                                var evt = root.haRainEvents[ir];
                                var rs = Math.max(evt.start, forecastStartR);
                                var re = Math.min(evt.end, forecastEndR);
                                if (rs >= re) continue;
                                var rx = ((rs - forecastStartR) / forecastSpanR) * w;
                                var rw = ((re - forecastStartR) / forecastSpanR) * w - rx;
                                ctx.fillRect(rx, h - h * 0.15, Math.max(rw, 2), h * 0.15);
                            }
                        }

                        // ── Wind area (subtle) ──
                        ctx.beginPath();
                        ctx.moveTo(0, h);
                        for (var iw2 = 0; iw2 < winds.length; iw2++) {
                            var wx = (iw2 / n) * w;
                            var wh = (winds[iw2] / wMax) * h * 0.2;  // bottom 20%
                            ctx.lineTo(wx, h - wh);
                        }
                        ctx.lineTo(w, h);
                        ctx.closePath();
                        ctx.fillStyle = Qt.rgba(1, 1, 1, 0.04);
                        ctx.fill();

                        // ── Temperature curve — filled gradient ──
                        // Fill below
                        ctx.beginPath();
                        ctx.moveTo(0, h);
                        for (var it = 0; it < n; it++) {
                            var tx = (it / n) * w;
                            var ty = h - ((temps[it] - tMin) / tRange) * h;
                            if (it === 0) ctx.lineTo(tx, ty);
                            else ctx.lineTo(tx, ty);
                        }
                        ctx.lineTo(w, h);
                        ctx.closePath();

                        var grad = ctx.createLinearGradient(0, 0, 0, h);
                        grad.addColorStop(0, Qt.rgba(1, 0.6, 0, 0.25));
                        grad.addColorStop(0.5, Qt.rgba(1, 0.8, 0.2, 0.08));
                        grad.addColorStop(1, Qt.rgba(0.4, 0.7, 1, 0.05));
                        ctx.fillStyle = grad;
                        ctx.fill();

                        // Temperature line
                        ctx.beginPath();
                        for (var it2 = 0; it2 < n; it2++) {
                            var tx2 = (it2 / n) * w;
                            var ty2 = h - ((temps[it2] - tMin) / tRange) * h;
                            if (it2 === 0) ctx.moveTo(tx2, ty2);
                            else ctx.lineTo(tx2, ty2);
                        }
                        var tempGrad = ctx.createLinearGradient(0, 0, w, 0);
                        for (var ig = 0; ig < n; ig += Math.max(1, Math.floor(n / 20))) {
                            var frac = ig / n;
                            var c = root.tempColor(temps[ig]);
                            tempGrad.addColorStop(frac, c);
                        }
                        ctx.strokeStyle = tempGrad;
                        ctx.lineWidth = 2;
                        ctx.stroke();

                        // ── HA sensor overlays ──
                        if (root.haLoaded && root.haSensors.length > 0 && times.length > 0) {
                            var forecastStart = new Date(times[0]).getTime();
                            var forecastEnd = new Date(times[n - 1]).getTime();
                            var forecastSpan = forecastEnd - forecastStart || 1;

                            for (var si = 0; si < root.haSensors.length; si++) {
                                var sensor = root.haSensors[si];
                                ctx.beginPath();
                                var haStarted = false;
                                for (var ih = 0; ih < sensor.times.length; ih++) {
                                    var haTs = sensor.times[ih];
                                    if (haTs < forecastStart || haTs > forecastEnd) continue;
                                    var hax = ((haTs - forecastStart) / forecastSpan) * w;
                                    var hay = h - ((sensor.temps[ih] - tMin) / tRange) * h;
                                    if (!haStarted) { ctx.moveTo(hax, hay); haStarted = true; }
                                    else ctx.lineTo(hax, hay);
                                }
                                if (haStarted) {
                                    ctx.strokeStyle = sensor.color;
                                    ctx.lineWidth = 1.5;
                                    ctx.stroke();
                                }
                            }
                        }

                        // ── "Now" marker ──
                        var now = new Date();
                        var nowIso = now.toISOString().substring(0, 13);
                        var nowIdx = -1;
                        for (var in2 = 0; in2 < times.length; in2++) {
                            if (times[in2].substring(0, 13) === nowIso) { nowIdx = in2; break; }
                        }
                        if (nowIdx >= 0) {
                            var nx = (nowIdx / n) * w;
                            var ny = h - ((temps[nowIdx] - tMin) / tRange) * h;
                            // Dashed line
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.3);
                            ctx.lineWidth = 1;
                            ctx.setLineDash([3, 3]);
                            ctx.beginPath();
                            ctx.moveTo(nx, 0);
                            ctx.lineTo(nx, h);
                            ctx.stroke();
                            ctx.setLineDash([]);
                            // Dot
                            ctx.beginPath();
                            ctx.arc(nx, ny, 4, 0, 2 * Math.PI);
                            ctx.fillStyle = "white";
                            ctx.fill();
                            ctx.beginPath();
                            ctx.arc(nx, ny, 2, 0, 2 * Math.PI);
                            ctx.fillStyle = root.tempColor(temps[nowIdx]);
                            ctx.fill();
                        }

                        // ── Hover tooltip ──
                        if (root.hoverIdx >= 0 && root.hoverIdx < n) {
                            var hi = root.hoverIdx;
                            var hx = (hi / n) * w;
                            var hy = h - ((temps[hi] - tMin) / tRange) * h;

                            // Crosshair
                            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.25);
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(hx, 0);
                            ctx.lineTo(hx, h);
                            ctx.stroke();

                            // Dot
                            ctx.beginPath();
                            ctx.arc(hx, hy, 3, 0, 2 * Math.PI);
                            ctx.fillStyle = "white";
                            ctx.fill();

                            // Tooltip
                            var time = times[hi] || "";
                            var hDate = new Date(time);
                            var hDays = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                            var hHH = hDate.getHours();
                            var hDay = hDays[hDate.getDay()];
                            var timeStr = hDay + " " + (hHH < 10 ? "0" : "") + hHH + ":00";
                            var label = Math.round(temps[hi]) + "°  " + root.weatherDesc(root.hourlyCode[hi]);
                            var line2 = "󰖗 " + precips[hi].toFixed(1) + "mm  󰖝 " + Math.round(winds[hi]) + "km/h";
                            var line3 = timeStr;

                            // Find matching HA sensor values
                            var haLines = [];
                            var haColors = [];
                            if (root.haLoaded && times[hi]) {
                                var hoverEpoch = new Date(times[hi]).getTime();
                                for (var isi = 0; isi < root.haSensors.length; isi++) {
                                    var sen = root.haSensors[isi];
                                    for (var iha = 0; iha < sen.times.length; iha++) {
                                        if (Math.abs(sen.times[iha] - hoverEpoch) < 1800000) {
                                            haLines.push(sen.label + ": " + sen.temps[iha].toFixed(1) + "°");
                                            haColors.push(sen.color);
                                            break;
                                        }
                                    }
                                }
                            }

                            var lines = [label, line2, line3];
                            for (var ihl = 0; ihl < haLines.length; ihl++) lines.push(haLines[ihl]);

                            ctx.font = "10px '" + AppConfig.Config.theme.fontFamily + "'";
                            var tw = 0;
                            for (var il = 0; il < lines.length; il++) {
                                var lw = ctx.measureText(lines[il]).width;
                                if (lw > tw) tw = lw;
                            }
                            var tooltipX = hx + 10;
                            if (tooltipX + tw + 12 > w) tooltipX = hx - tw - 20;
                            var boxH = 12 * lines.length + 6;
                            var tooltipY = Math.max(10, Math.min(hy - 24, h - boxH - 6));

                            // Background
                            ctx.fillStyle = Qt.rgba(0, 0, 0, 0.8);
                            var boxW = tw + 12;
                            var boxR = 4;
                            ctx.beginPath();
                            ctx.moveTo(tooltipX + boxR, tooltipY);
                            ctx.lineTo(tooltipX + boxW - boxR, tooltipY);
                            ctx.quadraticCurveTo(tooltipX + boxW, tooltipY, tooltipX + boxW, tooltipY + boxR);
                            ctx.lineTo(tooltipX + boxW, tooltipY + boxH - boxR);
                            ctx.quadraticCurveTo(tooltipX + boxW, tooltipY + boxH, tooltipX + boxW - boxR, tooltipY + boxH);
                            ctx.lineTo(tooltipX + boxR, tooltipY + boxH);
                            ctx.quadraticCurveTo(tooltipX, tooltipY + boxH, tooltipX, tooltipY + boxH - boxR);
                            ctx.lineTo(tooltipX, tooltipY + boxR);
                            ctx.quadraticCurveTo(tooltipX, tooltipY, tooltipX + boxR, tooltipY);
                            ctx.closePath();
                            ctx.fill();

                            // Text
                            ctx.textAlign = "left";
                            ctx.font = "bold 10px '" + AppConfig.Config.theme.fontFamily + "'";
                            ctx.fillStyle = "white";
                            ctx.fillText(label, tooltipX + 6, tooltipY + 13);
                            ctx.font = "10px '" + AppConfig.Config.theme.fontFamily + "'";
                            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.6);
                            ctx.fillText(line2, tooltipX + 6, tooltipY + 25);
                            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.4);
                            ctx.fillText(line3, tooltipX + 6, tooltipY + 37);
                            for (var iht = 0; iht < haLines.length; iht++) {
                                ctx.fillStyle = haColors[iht];
                                ctx.fillText(haLines[iht], tooltipX + 6, tooltipY + 49 + iht * 12);
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onPositionChanged: function(mouse) {
                            var n = root.hourlyTemp.length;
                            if (n === 0) return;
                            var idx = Math.round((mouse.x / parent.width) * n);
                            idx = Math.max(0, Math.min(n - 1, idx));
                            root.hoverIdx = idx;
                            root.hoverX = mouse.x;
                            graphCanvas.requestPaint();
                        }
                        onExited: {
                            root.hoverIdx = -1;
                            root.hoverX = -1;
                            graphCanvas.requestPaint();
                        }
                    }
                }
            }
        }
    }

    // Y-axis label positions
    property var yLabels: {
        if (hourlyTemp.length < 2) return [];
        var h = graphCanvas.height;
        if (h <= 0) return [];
        var tMin = hourlyTemp[0], tMax = hourlyTemp[0];
        for (var i = 0; i < hourlyTemp.length; i++) {
            if (hourlyTemp[i] < tMin) tMin = hourlyTemp[i];
            if (hourlyTemp[i] > tMax) tMax = hourlyTemp[i];
        }
        tMin = Math.floor(tMin / 5) * 5 - 2;
        tMax = Math.ceil(tMax / 5) * 5 + 2;
        var tRange = tMax - tMin || 1;
        var step = tRange <= 15 ? 5 : 10;
        var labels = [];
        for (var t = Math.ceil(tMin / step) * step; t <= tMax; t += step) {
            labels.push({ y: h - ((t - tMin) / tRange) * h, label: t + "°" });
        }
        return labels;
    }
}
