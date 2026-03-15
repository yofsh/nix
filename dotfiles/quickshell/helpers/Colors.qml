pragma Singleton
import QtQuick
import "../config" as AppConfig

QtObject {
    // General
    readonly property color background: AppConfig.Config.theme.colors.background
    readonly property color accent: AppConfig.Config.theme.colors.accent
    readonly property color textDefault: AppConfig.Config.theme.colors.textDefault
    readonly property color textMuted: AppConfig.Config.theme.colors.textMuted

    // Modules
    readonly property color cpu: AppConfig.Config.theme.colors.cpu
    readonly property color cpuUser: AppConfig.Config.theme.colors.cpuUser
    readonly property color memory: AppConfig.Config.theme.colors.memory
    readonly property color battery: AppConfig.Config.theme.colors.battery
    readonly property color batteryCharging: AppConfig.Config.theme.colors.batteryCharging
    readonly property color batteryWarning: AppConfig.Config.theme.colors.batteryWarning
    readonly property color batteryCritical: AppConfig.Config.theme.colors.batteryCritical
    readonly property color temperatureCritical: AppConfig.Config.theme.colors.temperatureCritical
    readonly property color headsetBattery: AppConfig.Config.theme.colors.headsetBattery
    readonly property color backlight: AppConfig.Config.theme.colors.backlight
    readonly property color mutedRed: AppConfig.Config.theme.colors.mutedRed
    readonly property color fingerprintOk: AppConfig.Config.theme.colors.fingerprintOk
    readonly property color fingerprintFail: AppConfig.Config.theme.colors.fingerprintFail
    readonly property color media: AppConfig.Config.theme.colors.media
    readonly property color windowTitle: AppConfig.Config.theme.colors.windowTitle
    readonly property color disconnected: AppConfig.Config.theme.colors.disconnected

    // Workspaces
    readonly property color wsActive: AppConfig.Config.theme.colors.wsActive
    readonly property color wsActiveBg: AppConfig.Config.theme.colors.wsActiveBg
    readonly property color wsEmpty: AppConfig.Config.theme.colors.wsEmpty
    readonly property color wsInactive: AppConfig.Config.theme.colors.wsInactive
    readonly property color wsUrgent: AppConfig.Config.theme.colors.wsUrgent

    // Submap
    readonly property color submapFg: AppConfig.Config.theme.colors.submapFg
    readonly property color submapBg: AppConfig.Config.theme.colors.submapBg
}
