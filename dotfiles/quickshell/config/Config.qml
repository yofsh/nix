pragma Singleton

import QtQuick
import "../core" as Core

QtObject {
    readonly property var theme: Core.ConfigService.section("theme", {
        fontFamily: "DejaVuSansM Nerd Font",
        barHeight: 22,
        barRadius: 5,
        surfaceRadius: 14,
        cardRadiusSmall: 8,
        surfaceOpacity: 0.8,
        surfaceOpacityStrong: 0.85,
        surfaceColor: "#11000000",
        // 0 = popup surfaces keep all four corners rounded (no upward
        // bleed under the bar). The bar-popup vertical gap is controlled
        // separately by `popupTopGap` below.
        surfaceTopBleed: 0,
        // Distance between the bar's bottom edge and the top edge of a
        // bar-anchored popup. Each popup uses
        //   margins.top: barHeight + popupTopGap
        // which keeps popups free-floating with a consistent breathing
        // room regardless of the bar height.
        popupTopGap: 12,
        popupSlideDuration: 150,
        interactiveHoverColor: "#14ffffff",
        interactiveHoverBorderColor: "#220caf49",
        interactiveHoverRadius: 4,
        interactiveHoverDuration: 120,
        spacingCompact: 2,
        spacingSmall: 4,
        spacingMedium: 6,
        spacingDefault: 8,
        fontSizeTiny: 10,
        fontSizeXSmall: 11,
        fontSizeSmall: 12,
        fontSizeBody: 13,
        fontSizeDefault: 14,
        fontSizeMedium: 15,
        popupFontSizeTiny: 11,
        popupFontSizeXSmall: 12,
        popupFontSizeSmall: 13,
        popupFontSizeBody: 14,
        popupFontSizeDefault: 16,
        popupFontSizeMedium: 17,
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
            gpu: "#26c6da",
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

    readonly property var gpu: Core.ConfigService.section("gpu", {
        usageColor: "#4dd0e1",
        memColor: "#80c882"
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
        transcribingFlag: "/tmp/voice_transcribing",
        typingFlag: "/tmp/voice_typing"
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

    readonly property var daemon: Core.ConfigService.section("daemon", {
        socket: "/run/user/1000/qs-daemon.sock"
    })

    readonly property var modules: Core.ConfigService.section("modules", {})
}
