pragma Singleton

import QtQuick
import "../core" as Core

QtObject {
    readonly property var theme: Core.ConfigService.section("theme", {
        fontFamily: "DejaVuSansM Nerd Font",
        barHeight: 22,
        surfaceRadius: 14,
        cardRadiusSmall: 8,
        surfaceOpacity: 0.8,
        surfaceOpacityStrong: 0.85,
        surfaceColor: "#11000000",
        surfaceTopBleed: 16,
        popupSlideDuration: 150,
        interactiveHoverColor: "#14ffffff",
        interactiveHoverBorderColor: "#220caf49",
        interactiveHoverRadius: 4,
        interactiveHoverDuration: 120,
        spacingCompact: 2,
        spacingSmall: 4,
        spacingMedium: 6,
        spacingDefault: 8,
        fontSizeTiny: 8,
        fontSizeXSmall: 9,
        fontSizeSmall: 10,
        fontSizeBody: 11,
        fontSizeDefault: 12,
        fontSizeMedium: 13,
        fontSizeIcon: 14,
        fontSizeIconLarge: 15,
        fontSizeTitleLarge: 24,
        fontSizeHero: 28,
        fontSizeDisplay: 36,
        fontSizeDisplayLarge: 48,
        colors: {
            background: "#000000",
            accent: "#0caf49",
            textDefault: "white",
            textMuted: "#80ffffff",
            cpu: "#ff9800",
            cpuUser: "#4caf50",
            memory: "#80c882",
            battery: "#1abc9c",
            batteryCharging: "#4caf50",
            batteryWarning: "#ff9800",
            batteryCritical: "#f53c3c",
            temperatureCritical: "#f53c3c",
            headsetBattery: "#3498db",
            backlight: "#bbbbbb",
            mutedRed: "#f53c3c",
            fingerprintOk: "#0caf49",
            fingerprintFail: "#f53c3c",
            media: "white",
            windowTitle: "white",
            disconnected: "#4dffffff",
            wsActive: "#0caf49",
            wsActiveBg: "#660caf49",
            wsEmpty: "#33ffffff",
            wsInactive: "#b3ffffff",
            wsUrgent: "#cc6666",
            submapFg: "#ffb74d",
            submapBg: "#33ff8c00"
        }
    })

    readonly property var network: Core.ConfigService.section("network", {
        gatewayTarget: ""
    })

    readonly property var backlight: Core.ConfigService.section("backlight", {
        devicePath: "",
        leftClickValue: "15%",
        rightClickValue: "1%",
        scrollStepUp: "5%+",
        scrollStepDown: "5%-"
    })

    readonly property var cpu: Core.ConfigService.section("cpu", {
        usageColor: "#ffb74d",
        performanceColor: "#f38ba8",
        balancedColor: "#a6e3a1",
        powerSaverColor: "#89b4fa"
    })

    readonly property var notifications: Core.ConfigService.section("notifications", {
        position: "top-left",
        horizontalOffset: 400,
        maxEntries: 40,
        maxVisible: 20,
        defaultBg: "#cc1a1a1a",
        defaultFg: "#eeeeee",
        dimText: "#59ffffff",
        mutedText: "#80ffffff",
        trackBg: "#26ffffff",
        timeoutBar: "white",
        timeoutBarOpacity: 0.2,
        fontFamily: "DejaVu Sans",
        fontSizeTitle: 12,
        fontSizeBody: 11,
        fontSizeSmall: 10,
        fontSizeMeta: 14,
        iconSize: 32,
        cardPadding: 8,
        cardRadius: 0,
        cardSpacing: 6,
        actionHeight: 22,
        actionRadius: 4,
        animEnter: 200,
        animExit: 150,
        animSlideOffset: 20
    })

    readonly property var wallpaper: Core.ConfigService.section("wallpaper", {
        directory: "",
        currentLink: "",
        previewTransitionType: "any",
        previewTransitionDuration: "0.4",
        previewTransitionFps: "240"
    })

    readonly property var voice: Core.ConfigService.section("voice", {
        dictatePidFile: "/tmp/voice_dictate.pid",
        claudePidFile: "/tmp/voice_claude.pid",
        streamPidFile: "/tmp/voice_stream.pid",
        transcribingFlag: "/tmp/voice_transcribing"
    })

    readonly property var weather: Core.ConfigService.section("weather", {
        city: "",
        latitude: 0,
        longitude: 0,
        refreshInterval: 900000,
        haUrl: "",
        haToken: "",
        haSensors: [],
        haRainSensor: "",
        haHistoryDays: 4
    })

    readonly property var bar: Core.ConfigService.section("bar", {
        left: [],
        center: [],
        right: []
    })

    readonly property var modules: Core.ConfigService.section("modules", {})
}
