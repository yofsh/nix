pragma Singleton
import QtQuick

QtObject {
    // General
    readonly property color background: "#000000"
    readonly property color accent: "#0caf49"
    readonly property color textDefault: "white"
    readonly property color textMuted: Qt.rgba(1, 1, 1, 0.5)

    // Modules
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

    // Workspaces
    readonly property color wsActive: "#0caf49"
    readonly property color wsActiveBg: Qt.rgba(0.047, 0.686, 0.286, 0.4)
    readonly property color wsEmpty: Qt.rgba(1, 1, 1, 0.2)
    readonly property color wsInactive: Qt.rgba(1, 1, 1, 0.7)
    readonly property color wsUrgent: "#cc6666"

    // Submap
    readonly property color submapFg: "#222"
    readonly property color submapBg: "#eee"
}
