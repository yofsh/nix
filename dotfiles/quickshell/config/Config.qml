pragma Singleton
import QtQuick

QtObject {
    readonly property QtObject theme: QtObject {
        readonly property string fontFamily: "DejaVuSansM Nerd Font"
        readonly property int barHeight: 22
        readonly property int surfaceRadius: 0
        readonly property int cardRadiusSmall: 8
        readonly property real surfaceOpacity: 0.8
        readonly property real surfaceOpacityStrong: 0.85
        readonly property color surfaceColor: "#11000000"
        readonly property int surfaceTopBleed: 16
        readonly property int popupSlideDuration: 150
        readonly property int spacingCompact: 2
        readonly property int spacingSmall: 4
        readonly property int spacingMedium: 6
        readonly property int spacingDefault: 8
        readonly property int fontSizeTiny: 8
        readonly property int fontSizeXSmall: 9
        readonly property int fontSizeSmall: 10
        readonly property int fontSizeBody: 11
        readonly property int fontSizeDefault: 12
        readonly property int fontSizeMedium: 13
        readonly property int fontSizeIcon: 14
        readonly property int fontSizeIconLarge: 15
        readonly property int fontSizeTitleLarge: 24
        readonly property int fontSizeHero: 28
        readonly property int fontSizeDisplay: 36
        readonly property int fontSizeDisplayLarge: 48

        readonly property QtObject colors: QtObject {
            readonly property color background: "#000000"
            readonly property color accent: "#0caf49"
            readonly property color textDefault: "white"
            readonly property color textMuted: Qt.rgba(1, 1, 1, 0.5)

            readonly property color cpu: "#ff9800"
            readonly property color cpuUser: "#4caf50"
            readonly property color memory: "#80c882"
            readonly property color battery: "#1abc9c"
            readonly property color batteryCharging: "#4caf50"
            readonly property color batteryWarning: "#ff9800"
            readonly property color batteryCritical: "#f53c3c"
            readonly property color temperatureCritical: "#f53c3c"
            readonly property color headsetBattery: "#3498db"
            readonly property color backlight: "#bbb"
            readonly property color mutedRed: "#f53c3c"
            readonly property color fingerprintOk: "#0caf49"
            readonly property color fingerprintFail: "#f53c3c"
            readonly property color media: "white"
            readonly property color windowTitle: "white"
            readonly property color disconnected: Qt.rgba(1, 1, 1, 0.3)

            readonly property color wsActive: "#0caf49"
            readonly property color wsActiveBg: Qt.rgba(0.047, 0.686, 0.286, 0.4)
            readonly property color wsEmpty: Qt.rgba(1, 1, 1, 0.2)
            readonly property color wsInactive: Qt.rgba(1, 1, 1, 0.7)
            readonly property color wsUrgent: "#cc6666"

            readonly property color submapFg: "#222"
            readonly property color submapBg: "#eee"

            readonly property color multimeter: "#f9e2af"
            readonly property color multimeterActive: "#a6e3a1"
            readonly property color multimeterError: "#f38ba8"
            readonly property color multimeterIdle: Qt.rgba(1, 1, 1, 0.35)
        }
    }

    readonly property QtObject network: QtObject {
        readonly property string gatewayTarget: "hermes"
    }

    readonly property QtObject backlight: QtObject {
        readonly property string devicePath: "/sys/class/backlight/intel_backlight"
        readonly property string leftClickValue: "15%"
        readonly property string rightClickValue: "1%"
        readonly property string scrollStepUp: "5%+"
        readonly property string scrollStepDown: "5%-"
    }

    readonly property QtObject cpu: QtObject {
        readonly property color usageColor: "#ffb74d"
        readonly property color performanceColor: "#f38ba8"
        readonly property color balancedColor: "#a6e3a1"
        readonly property color powerSaverColor: "#89b4fa"
    }

    readonly property QtObject notifications: QtObject {
        readonly property string position: "top-left"
        readonly property int horizontalOffset: 400
        readonly property int maxEntries: 40
        readonly property int maxVisible: 20

        readonly property color defaultBg: "#cc1a1a1a"
        readonly property color defaultFg: "#eeeeee"
        readonly property color dimText: Qt.rgba(1, 1, 1, 0.35)
        readonly property color mutedText: Qt.rgba(1, 1, 1, 0.5)
        readonly property color trackBg: Qt.rgba(1, 1, 1, 0.15)
        readonly property color timeoutBar: "white"
        readonly property real timeoutBarOpacity: 0.2

        readonly property string fontFamily: "DejaVu Sans"
        readonly property int fontSizeTitle: 12
        readonly property int fontSizeBody: 11
        readonly property int fontSizeSmall: 10
        readonly property int fontSizeMeta: 14

        readonly property int iconSize: 32
        readonly property int cardPadding: 8
        readonly property int cardRadius: 0
        readonly property int cardSpacing: 6
        readonly property int actionHeight: 22
        readonly property int actionRadius: 4

        readonly property int animEnter: 200
        readonly property int animExit: 150
        readonly property int animSlideOffset: 20
    }

    readonly property QtObject wallpaper: QtObject {
        readonly property string directory: "$HOME/pics/wallpapers"
        readonly property string currentLink: "$HOME/.current-wallpaper"
        readonly property string previewTransitionType: "any"
        readonly property string previewTransitionDuration: "0.4"
        readonly property string previewTransitionFps: "240"
    }

    readonly property QtObject voice: QtObject {
        readonly property string dictatePidFile: "/tmp/voice_dictate.pid"
        readonly property string claudePidFile: "/tmp/voice_claude.pid"
        readonly property string streamPidFile: "/tmp/voice_stream.pid"
        readonly property string transcribingFlag: "/tmp/voice_transcribing"
    }

    readonly property QtObject weather: QtObject {
        readonly property string city: "Blanes"
        readonly property real latitude: 41.67419
        readonly property real longitude: 2.79036
        readonly property int refreshInterval: 900000  // 15 minutes
        readonly property string haUrl: "http://192.168.8.30:8123"
        readonly property string haToken: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI1ZWNiOWFlNDBjMmM0NWQwOTA5YmJjNWMzNDkwZWRmYyIsImlhdCI6MTc2NjU4MTkxMiwiZXhwIjoyMDgxOTQxOTEyfQ.HfZ8z2PZTocK8YH8P5QzbkUD7yB8_-2AUVyKdjhc5iU"
        readonly property var haSensors: [
            { entityId: "sensor.atc_ee61_temperature", label: "Balcony", color: "#4caf50" },
            { entityId: "sensor.atc_fbd5_temperature", label: "Outdoor", color: "#42a5f5" }
        ]
        readonly property string haRainSensor: "sensor.zb_outdoor_1_rainwater"
        readonly property int haHistoryDays: 4
    }
}
