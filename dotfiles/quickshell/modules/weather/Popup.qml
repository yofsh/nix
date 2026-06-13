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

    implicitWidth: 1460
    implicitHeight: 430

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
    property real dewPoint: 0
    property real visibilityKm: 0
    property real uvNow: 0
    property bool dataLoaded: false

    // Daily (today)
    property string sunrise: ""
    property string sunset: ""
    property real uvIndex: 0
    property real dailyPrecipSum: 0
    property int dailyPrecipProb: 0
    property real dailyWindMax: 0
    property real sunshineSecs: 0
    property real daylightSecs: 0
    property var dailySunrise: []
    property var dailySunset: []

    // Air quality
    property int euAqi: 0
    property real pm25: 0
    property real pm10: 0
    property real no2: 0
    property real o3: 0
    property real so2: 0
    property real co: 0
    property var pollen: []  // [{name, val}] active pollens, worst first
    property bool aqLoaded: false

    // Hourly forecast (for graph)
    property var hourlyTime: []
    property var hourlyTemp: []
    property var hourlyPrecip: []
    property var hourlyWind: []
    property var hourlyCode: []
    property var hourlyPressure: []
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

    // Bumped by the 10 s popup timer so time-based bindings (countdowns) re-evaluate
    property int nowTick: 0

    function updateAgo() {
        nowTick++;
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

    // Local "YYYY-MM-DDTHH" key — hourlyTime is local ISO (timezone=auto),
    // so never compare against toISOString() (UTC).
    function localHourStr(d) {
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0")
            + "-" + String(d.getDate()).padStart(2, "0")
            + "T" + String(d.getHours()).padStart(2, "0");
    }

    function nowIndex() {
        var key = localHourStr(new Date());
        for (var i = 0; i < hourlyTime.length; i++)
            if (hourlyTime[i].substring(0, 13) === key) return i;
        return -1;
    }

    // Pressure tendency over the last 3 h: ↗ rising / → steady / ↘ falling
    readonly property string pressureTrend: {
        var i = nowIndex();
        if (i < 3 || hourlyPressure.length <= i) return "";
        var diff = hourlyPressure[i] - hourlyPressure[i - 3];
        if (diff > 0.8) return "↗";
        if (diff < -0.8) return "↘";
        return "→";
    }
    readonly property color pressureTrendColor:
        pressureTrend === "↗" ? "#8bc34a" : pressureTrend === "↘" ? "#ff9800" : Helpers.Colors.textMuted

    // First forecast hour with measurable precipitation from now on
    readonly property string nextRainLabel: {
        var i = nowIndex();
        if (i < 0 || hourlyPrecip.length === 0) return "--";
        for (var k = i; k < hourlyPrecip.length; k++) {
            if (hourlyPrecip[k] >= 0.1) {
                var dh = k - i;
                if (dh <= 0) return "now";
                if (dh < 24) return "in " + dh + "h";
                return dayName(hourlyTime[k].substring(0, 10)) + " " + hourlyTime[k].substring(11, 16);
            }
        }
        return "none in 5d";
    }
    readonly property bool rainSoon: nextRainLabel === "now" || (nextRainLabel.indexOf("in ") === 0 && parseInt(nextRainLabel.substring(3)) <= 6)

    function fmtDuration(secs) {
        if (secs <= 0) return "--";
        var h = Math.floor(secs / 3600);
        var m = Math.round((secs % 3600) / 60);
        return h + "h " + (m < 10 ? "0" : "") + m + "m";
    }

    // Time until the next event in a daily ISO-timestamp array (sunrise/sunset)
    function nextEventCountdown(arr) {
        var now = Date.now();
        for (var i = 0; i < arr.length; i++) {
            var t = new Date(arr[i]).getTime();
            if (!isNaN(t) && t > now) {
                var mins = Math.round((t - now) / 60000);
                var h = Math.floor(mins / 60), m = mins % 60;
                return h > 0 ? h + "h " + (m < 10 ? "0" : "") + m + "m" : m + "m";
            }
        }
        return "--";
    }

    readonly property string sunriseCountdown: { nowTick; return nextEventCountdown(dailySunrise); }
    readonly property string sunsetCountdown: { nowTick; return nextEventCountdown(dailySunset); }

    function pollenColor(v) {
        if (v < 20) return "#8bc34a";
        if (v < 70) return "#ff9800";
        return "#f53c3c";
    }

    function windColor(v) {
        if (v >= 60) return "#f53c3c";
        if (v >= 30) return "#ff9800";
        return Helpers.Colors.textDefault;
    }

    function humidityColor(h) {
        if (h >= 80) return "#64b5f6";
        if (h <= 25) return "#ff9800";
        return Helpers.Colors.textDefault;
    }

    // Dew point = muggy threshold, not air temp
    function dewPointColor(d) {
        if (d >= 21) return "#f53c3c";
        if (d >= 18) return "#ff9800";
        return Helpers.Colors.textDefault;
    }

    function pressureColor(p) {
        if (p < 985) return "#f53c3c";
        if (p < 1000) return "#ff9800";
        return Helpers.Colors.textDefault;
    }

    function visibilityColor(km) {
        if (km < 1) return "#f53c3c";
        if (km < 4) return "#ff9800";
        return Helpers.Colors.textDefault;
    }

    // EU AQI pollutant bands (µg/m³): default = good, then moderate/poor/very poor
    function pollutantColor(kind, v) {
        var bands = {
            pm25: [25, 50, 75],
            pm10: [50, 100, 150],
            o3:   [130, 240, 380],
            no2:  [120, 230, 340]
        }[kind];
        if (v >= bands[2]) return "#9c27b0";
        if (v >= bands[1]) return "#f53c3c";
        if (v >= bands[0]) return "#ff9800";
        return Helpers.Colors.textDefault;
    }

    // Sunshine fraction of daylight: golden when sunny, muted when grey
    function sunshineColor(sun, day) {
        if (day <= 0) return Helpers.Colors.textDefault;
        var r = sun / day;
        if (r >= 0.6) return "#ffd54f";
        if (r < 0.25) return Helpers.Colors.textMuted;
        return Helpers.Colors.textDefault;
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
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day,cloud_cover,pressure_msl,precipitation,visibility,uv_index"
            + "&hourly=temperature_2m,precipitation,wind_speed_10m,weather_code,pressure_msl"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,wind_direction_10m_dominant,sunrise,sunset,uv_index_max,sunshine_duration,daylight_duration"
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
                root.pressure = c.pressure_msl;
                root.precipitation = c.precipitation;
                root.dewPoint = c.dew_point_2m;
                root.visibilityKm = (c.visibility || 0) / 1000;
                root.uvNow = c.uv_index || 0;
                root.dataLoaded = true;
            }
            if (data.hourly) {
                root.hourlyTime = data.hourly.time;
                root.hourlyTemp = data.hourly.temperature_2m;
                root.hourlyPrecip = data.hourly.precipitation;
                root.hourlyWind = data.hourly.wind_speed_10m;
                root.hourlyCode = data.hourly.weather_code;
                root.hourlyPressure = data.hourly.pressure_msl;
            }
            if (data.daily) {
                var d = data.daily;
                // daily starts past_days ago — find today's index, don't use [0]
                var ti = d.time.indexOf(root.localHourStr(new Date()).substring(0, 10));
                if (ti < 0) ti = 0;
                root.sunrise = d.sunrise[ti] || "";
                root.sunset = d.sunset[ti] || "";
                root.uvIndex = d.uv_index_max[ti] || 0;
                root.dailyPrecipSum = d.precipitation_sum[ti] || 0;
                root.dailyPrecipProb = d.precipitation_probability_max[ti] || 0;
                root.dailyWindMax = d.wind_speed_10m_max[ti] || 0;
                root.sunshineSecs = d.sunshine_duration[ti] || 0;
                root.daylightSecs = d.daylight_duration[ti] || 0;
                root.dailySunrise = d.sunrise;
                root.dailySunset = d.sunset;
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
            + "&current=european_aqi,pm10,pm2_5,nitrogen_dioxide,ozone,sulphur_dioxide,carbon_monoxide,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
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
                var defs = [
                    { name: "Grass", val: c.grass_pollen || 0 },
                    { name: "Olive", val: c.olive_pollen || 0 },
                    { name: "Birch", val: c.birch_pollen || 0 },
                    { name: "Alder", val: c.alder_pollen || 0 },
                    { name: "Mugwort", val: c.mugwort_pollen || 0 },
                    { name: "Ragweed", val: c.ragweed_pollen || 0 }
                ];
                var act = defs.filter(function(p) { return p.val >= 1; });
                act.sort(function(a, b) { return b.val - a.val; });
                root.pollen = act.slice(0, 2);
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
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                popup: root
            }

            // ── Graph section: forecast ──
            ForecastChart {
                id: forecastChart
                anchors.top: topSection.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                popup: root
            }
        }
    }
}
