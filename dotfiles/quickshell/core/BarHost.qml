//@ pragma IconTheme Papirus
import Quickshell
import Quickshell.Io
import QtQuick
import "../helpers" as Helpers
import "../popups" as Popups
import "." as Core
import "../config" as AppConfig
// Bar widgets are statically linked (not Loader/Repeater) so Quickshell's
// reloader can match them across reloads — module edits hot-reload smoothly.
import "../modules/window-title" as M_window_title
import "../modules/workspaces" as M_workspaces
import "../modules/voice-recording" as M_voice_recording
import "../modules/wf-recorder" as M_wf_recorder
import "../modules/privacy-indicators" as M_privacy_indicators
import "../modules/transmission" as M_transmission
import "../modules/yts" as M_yts
import "../modules/media" as M_media
import "../modules/backlight" as M_backlight
import "../modules/app-usage" as M_app_usage
import "../modules/focus" as M_focus
import "../modules/claude-usage" as M_claude_usage
import "../modules/claude-sessions" as M_claude_sessions
import "../modules/network" as M_network
import "../modules/ping-gw" as M_ping_gw
import "../modules/ping" as M_ping
import "../modules/system-group" as M_system_group
import "../modules/weather" as M_weather
import "../modules/battery" as M_battery
import "../modules/airpods" as M_airpods
import "../modules/khal" as M_khal
import "../modules/headset-battery" as M_headset_battery
import "../modules/volume" as M_volume
import "../modules/systray" as M_systray
import "../modules/language" as M_language
import "../modules/notification-icon" as M_notification_icon
// popup-only modules (no bar widget): cpu/system/temperature are shown via system-group, wallpaper via keybind
import "../modules/cpu" as M_cpu
import "../modules/system" as M_system
import "../modules/temperature" as M_temperature
import "../modules/wallpaper" as M_wallpaper

PanelWindow {
    id: bar

    required property var screen
    property bool polkitActive: false
    property var fingerprintMonitor: null

    readonly property var theme: AppConfig.Config.theme
    readonly property string screenName: screen && screen.name ? screen.name : "global"

    anchors {
        top: true
        left: true
        right: true
    }

    margins.top: 0
    color: "transparent"
    implicitHeight: theme.barHeight

    // Shared wiring for every module entry below: BarWidget/BarPopup pin the
    // module to this window's screen, BarPopup additionally to this bar window.
    component BarWidget: Core.PackageWidget {
        screen: bar.screen
    }
    component BarPopup: Core.PackagePopup {
        screen: bar.screen
        barWindow: bar
    }

    // Dev tooling: the bar surface spans the monitor but the visible content is
    // this centered block — expose its window-relative geometry over IPC so
    // .claude/skills/qs/scripts/qs-popup can screenshot exactly the visible bar.
    // First screen only (duplicate IpcHandler targets would collide).
    Loader {
        active: bar.screen === Quickshell.screens[0]
        sourceComponent: IpcHandler {
            target: "bar"
            function geometry(): string {
                return JSON.stringify({ x: barContent.x, y: barContent.y, w: barContent.width, h: barContent.height, screen: bar.screenName });
            }
        }
    }

    Item {
        id: barContent
        anchors.centerIn: parent
        width: Math.max(contentRow.implicitWidth, contentRow.childrenRect.width) + 16
        height: parent.height

        Rectangle {
            anchors.fill: parent
            color: {
                var src = Qt.color(submapOverlay.submapName !== "" ? Helpers.Colors.submapBg : bar.theme.surfaceColor);
                return Qt.rgba(src.r, src.g, src.b, src.a * bar.theme.surfaceOpacity);
            }
            antialiasing: true
            radius: bar.theme.barRadius
            layer.enabled: true
            layer.samples: 8
            layer.smooth: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: bar.theme.spacingDefault
            height: parent.height - 4

            Row {
                id: leftSection
                spacing: bar.theme.spacingDefault
                width: implicitWidth
                height: parent.height

                BarWidget { moduleId: "window-title"; M_window_title.Widget {} }
                BarWidget { moduleId: "workspaces"; M_workspaces.Widget {} }
                BarWidget { moduleId: "voice-recording"; M_voice_recording.Widget {} }
                BarWidget { moduleId: "wf-recorder"; M_wf_recorder.Widget {} }
                BarWidget { moduleId: "privacy-indicators"; M_privacy_indicators.Widget {} }
                BarWidget { moduleId: "transmission"; M_transmission.Widget {} }
                BarWidget { moduleId: "yts"; M_yts.Widget {} }
                BarWidget { moduleId: "media"; M_media.Widget {} }
                BarWidget { moduleId: "backlight"; M_backlight.Widget {} }
                BarWidget { moduleId: "app-usage"; M_app_usage.Widget {} }
                BarWidget { moduleId: "focus"; M_focus.Widget {} }
                BarWidget { moduleId: "claude-usage"; M_claude_usage.Widget {} }
                BarWidget { moduleId: "claude-sessions"; M_claude_sessions.Widget {} }
                BarWidget { moduleId: "network"; M_network.Widget {} }
                BarWidget { moduleId: "ping-gw"; M_ping_gw.Widget {} }
                BarWidget { moduleId: "ping"; M_ping.Widget {} }
                BarWidget { moduleId: "system-group"; M_system_group.Widget {} }
                BarWidget { moduleId: "weather"; M_weather.Widget {} }
                BarWidget { moduleId: "battery"; M_battery.Widget {} }
                BarWidget { moduleId: "airpods"; M_airpods.Widget {} }
            }

            Row {
                id: centerSection
                spacing: bar.theme.spacingDefault
                visible: children.length > 0
                width: visible ? implicitWidth : 0
                height: parent.height
                // (no center widgets currently)
            }

            Row {
                id: rightSection
                spacing: bar.theme.spacingDefault
                width: implicitWidth
                height: parent.height

                BarWidget { moduleId: "khal"; M_khal.Widget {} }
                BarWidget { moduleId: "headset-battery"; M_headset_battery.Widget {} }
                BarWidget { moduleId: "volume"; M_volume.Widget {} }
                BarWidget { moduleId: "systray"; M_systray.Widget {} }
                BarWidget { moduleId: "language"; M_language.Widget {} }
                BarWidget { moduleId: "notification-icon"; M_notification_icon.Widget {} }
            }
        }
    }

    // Popups — statically linked. PackagePopup provides each window's placement,
    // open/close state, click-out and IPC; the module file is just content.
    BarPopup { moduleId: "app-usage";       M_app_usage.Popup {} }
    BarPopup { moduleId: "battery";         M_battery.Popup {} }
    BarPopup { moduleId: "claude-usage";    M_claude_usage.Popup {} }
    BarPopup { moduleId: "claude-sessions"; M_claude_sessions.Popup {} }
    BarPopup { moduleId: "cpu";             M_cpu.Popup {} }
    BarPopup { moduleId: "focus";           keyboardFocus: true; M_focus.Popup {} }
    BarPopup { moduleId: "khal";            M_khal.Popup {} }
    BarPopup { moduleId: "network";         ipc: false; M_network.Popup {} }
    BarPopup { moduleId: "system";          M_system.Popup {} }
    BarPopup { moduleId: "temperature";     M_temperature.Popup {} }
    BarPopup { moduleId: "weather";         M_weather.Popup {} }

    // wallpaper is its own window (WlrLayershell keyboard focus); host only sets screen
    M_wallpaper.Popup { screen: bar.screen }

    Popups.NotificationPopup {
        screen: bar.screen
        barHeight: bar.implicitHeight

        Component.onCompleted: Core.ModuleRegistry.registerWindowInstance("notifications", bar.screenName, this)
        Component.onDestruction: Core.ModuleRegistry.unregisterWindowInstance("notifications", bar.screenName)
    }

    Popups.OsdPopup {
        screen: bar.screen
        barHeight: bar.implicitHeight
    }

    Popups.FingerprintPopup {
        screen: bar.screen
        barHeight: bar.implicitHeight
        polkitActive: bar.polkitActive
        fingerprintMonitor: bar.fingerprintMonitor
    }

    Core.SubmapOverlay {
        id: submapOverlay
        screen: bar.screen
    }
}
