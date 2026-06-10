import Quickshell.Io
import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
// Composition root: owns all weather data, fetching and helper functions, and
// lays out the sections — CurrentConditions on top, ForecastChart below
// — passing itself to them as `popup`.
Item {
    id: root
    property bool popupOpen: false
    property real latitude: AppConfig.Config.weather.latitude
    property real longitude: AppConfig.Config.weather.longitude
    property string cityName: AppConfig.Config.weather.city

    implicitWidth: 1020
    implicitHeight: 380

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
        weatherFetch.reload();
        aqFetch.reload();
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

    // Open-meteo forecast — plain HTTPS, so DaemonFetch (url mode) provides the
    // kill-and-restart + stale-response guard. Driven by refreshAll(), not its
    // own interval (the adaptive background Timer below sets the cadence).
    Helpers.DaemonFetch {
        id: weatherFetch
        url: "https://api.open-meteo.com/v1/forecast?latitude=" + root.latitude
            + "&longitude=" + root.longitude
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day,cloud_cover,surface_pressure,precipitation"
            + "&hourly=temperature_2m,precipitation,wind_speed_10m,weather_code"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,sunrise,sunset,uv_index_max"
            + "&timezone=auto&forecast_days=5&past_days=" + AppConfig.Config.weather.haHistoryDays
        fetchOnActive: false
        onJson: data => {
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
            forecastChart.requestPaint();
        }
    }

    // Open-meteo air quality — plain HTTPS, same DaemonFetch treatment.
    Helpers.DaemonFetch {
        id: aqFetch
        url: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=" + root.latitude
            + "&longitude=" + root.longitude
            + "&current=european_aqi,pm10,pm2_5,nitrogen_dioxide,ozone,sulphur_dioxide,carbon_monoxide"
            + "&timezone=auto"
        fetchOnActive: false
        onJson: data => {
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
        }
    }

    // HA sensor history — fetch all configured sensors via one curl (comma-separated entity_ids).
    // Needs an Authorization header, which DaemonFetch does not support — stays a Process.
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
            forecastChart.requestPaint();
        } catch (e) {}
    }

    // HA live sensor states (temp + humidity) — auth header + jq pipeline, stays a Process.
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

    // HA rain sensor history — auth header, stays a Process.
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
                    forecastChart.requestPaint();
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
            CurrentConditions {
                id: topSection
                anchors.top: parent.top
                anchors.topMargin: 14
                anchors.horizontalCenter: parent.horizontalCenter
                popup: root
            }

            // ── Graph section: forecast ──
            ForecastChart {
                id: forecastChart
                anchors.top: topSection.bottom
                anchors.topMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                popup: root
            }
        }
    }
}
