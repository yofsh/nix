//@ pragma IconTheme Papirus
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../helpers" as Helpers
import "../components" as Components
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
// popup-only modules (no bar widget): system/temperature are shown via system-group, wallpaper via keybind
import "../modules/system" as M_system
import "../modules/temperature" as M_temperature
import "../modules/wallpaper" as M_wallpaper

PanelWindow {
    id: barWindow

    required property var screen
    property bool polkitActive: false
    property var fingerprintMonitor: null

    readonly property var theme: Core.ConfigService.section("theme", {})
    readonly property var hostScreenInfo: screen
    readonly property string hostScreenName: hostScreenInfo && hostScreenInfo.name ? hostScreenInfo.name : "global"
    property string submapName: ""
    property var submapBinds: []
    property real submapComboWidth: 0
    property var keybindsData: null
    // Noticeably larger fonts for the submap cheatsheet overlay
    readonly property int submapBindFontSize: Math.round((theme.fontSizeDefault || 14) * 1.5)
    readonly property int submapTitleFontSize: Math.round((theme.fontSizeDefault || 14) * 1.9)

    anchors {
        top: true
        left: true
        right: true
    }

    margins.top: 0
    color: "transparent"
    implicitHeight: theme.barHeight || 22

    Process {
        id: keybindsProc
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/keybinds/list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    barWindow.keybindsData = JSON.parse(this.text);
                    barWindow.updateSubmapBinds();
                } catch (error) {
                    console.warn("hypr-keybinds parse error:", error);
                }
            }
        }
    }

    Text {
        id: comboMeasure
        visible: false
        font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
        font.pixelSize: barWindow.submapBindFontSize
        font.bold: true
    }

    function updateSubmapBinds() {
        if (!submapName || !keybindsData || !keybindsData.submaps)
            return;

        for (var i = 0; i < keybindsData.submaps.length; i++) {
            var submap = keybindsData.submaps[i];
            if (submap.name !== submapName)
                continue;

            var entries = [];
            var maxWidth = 0;

            for (var j = 0; j < submap.binds.length; j++) {
                var pretty = submap.binds[j].pretty || "";
                var separator = pretty.indexOf(" \u2014 ");
                var combo = separator >= 0 ? pretty.substring(0, separator) : pretty;
                var description = separator >= 0 ? pretty.substring(separator + 3) : "";

                comboMeasure.text = combo;
                if (comboMeasure.implicitWidth > maxWidth)
                    maxWidth = comboMeasure.implicitWidth;

                entries.push({ combo: combo, desc: description });
            }

            submapBinds = entries;
            submapComboWidth = maxWidth;
            return;
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "submap")
                return;

            barWindow.submapName = event.data.trim();
            barWindow.updateSubmapBinds();
            if (barWindow.submapName)
                keybindsProc.running = true;
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
                var src = Qt.color(barWindow.submapName !== "" ? Helpers.Colors.submapBg : (theme.surfaceColor || "#11000000"));
                var op = theme.surfaceOpacity !== undefined ? theme.surfaceOpacity : 0.8;
                return Qt.rgba(src.r, src.g, src.b, src.a * op);
            }
            antialiasing: true
            radius: theme.barRadius !== undefined ? theme.barRadius : (theme.surfaceRadius || 0)
            layer.enabled: true
            layer.samples: 8
            layer.smooth: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: theme.spacingDefault || 8
            height: parent.height - 4

            Row {
                id: leftSection
                spacing: theme.spacingDefault || 8
                width: implicitWidth
                height: parent.height

                Core.PackageWidget { moduleId: "window-title"; screen: hostScreenInfo; M_window_title.Widget {} }
                Core.PackageWidget { moduleId: "workspaces"; screen: hostScreenInfo; M_workspaces.Widget {} }
                Core.PackageWidget { moduleId: "voice-recording"; screen: hostScreenInfo; M_voice_recording.Widget {} }
                Core.PackageWidget { moduleId: "wf-recorder"; screen: hostScreenInfo; M_wf_recorder.Widget {} }
                Core.PackageWidget { moduleId: "privacy-indicators"; screen: hostScreenInfo; M_privacy_indicators.Widget {} }
                Core.PackageWidget { moduleId: "transmission"; screen: hostScreenInfo; M_transmission.Widget {} }
                Core.PackageWidget { moduleId: "yts"; screen: hostScreenInfo; M_yts.Widget {} }
                Core.PackageWidget { moduleId: "media"; screen: hostScreenInfo; M_media.Widget {} }
                Core.PackageWidget { moduleId: "backlight"; screen: hostScreenInfo; M_backlight.Widget {} }
                Core.PackageWidget { moduleId: "app-usage"; screen: hostScreenInfo; M_app_usage.Widget {} }
                Core.PackageWidget { moduleId: "focus"; screen: hostScreenInfo; M_focus.Widget {} }
                Core.PackageWidget { moduleId: "claude-usage"; screen: hostScreenInfo; M_claude_usage.Widget {} }
                Core.PackageWidget { moduleId: "network"; screen: hostScreenInfo; M_network.Widget {} }
                Core.PackageWidget { moduleId: "ping-gw"; screen: hostScreenInfo; M_ping_gw.Widget {} }
                Core.PackageWidget { moduleId: "ping"; screen: hostScreenInfo; M_ping.Widget {} }
                Core.PackageWidget { moduleId: "system-group"; screen: hostScreenInfo; M_system_group.Widget {} }
                Core.PackageWidget { moduleId: "weather"; screen: hostScreenInfo; M_weather.Widget {} }
                Core.PackageWidget { moduleId: "battery"; screen: hostScreenInfo; M_battery.Widget {} }
                Core.PackageWidget { moduleId: "airpods"; screen: hostScreenInfo; M_airpods.Widget {} }
            }

            Row {
                id: centerSection
                spacing: theme.spacingDefault || 8
                visible: children.length > 0
                width: visible ? implicitWidth : 0
                height: parent.height
                // (no center widgets currently)
            }

            Row {
                id: rightSection
                spacing: theme.spacingDefault || 8
                width: implicitWidth
                height: parent.height

                Core.PackageWidget { moduleId: "khal"; screen: hostScreenInfo; M_khal.Widget {} }
                Core.PackageWidget { moduleId: "headset-battery"; screen: hostScreenInfo; M_headset_battery.Widget {} }
                Core.PackageWidget { moduleId: "volume"; screen: hostScreenInfo; M_volume.Widget {} }
                Core.PackageWidget { moduleId: "systray"; screen: hostScreenInfo; M_systray.Widget {} }
                Core.PackageWidget { moduleId: "language"; screen: hostScreenInfo; M_language.Widget {} }
                Core.PackageWidget { moduleId: "notification-icon"; screen: hostScreenInfo; M_notification_icon.Widget {} }
            }
        }
    }

    // Popups — statically linked. PackagePopup provides each window's placement,
    // open/close state, click-out and IPC; the module file is just content.
    Core.PackagePopup { moduleId: "app-usage";    screen: hostScreenInfo; barWindow: barWindow; M_app_usage.Popup {} }
    Core.PackagePopup { moduleId: "battery";      screen: hostScreenInfo; barWindow: barWindow; M_battery.Popup {} }
    Core.PackagePopup { moduleId: "claude-usage"; screen: hostScreenInfo; barWindow: barWindow; M_claude_usage.Popup {} }
    Core.PackagePopup { moduleId: "focus";        screen: hostScreenInfo; barWindow: barWindow; keyboardFocus: true; M_focus.Popup {} }
    Core.PackagePopup { moduleId: "khal";         screen: hostScreenInfo; barWindow: barWindow; M_khal.Popup {} }
    Core.PackagePopup { moduleId: "network";      screen: hostScreenInfo; barWindow: barWindow; ipc: false; M_network.Popup {} }
    Core.PackagePopup { moduleId: "system";       screen: hostScreenInfo; barWindow: barWindow; M_system.Popup {} }
    Core.PackagePopup { moduleId: "temperature";  screen: hostScreenInfo; barWindow: barWindow; M_temperature.Popup {} }
    Core.PackagePopup { moduleId: "weather";      screen: hostScreenInfo; barWindow: barWindow; M_weather.Popup {} }

    // wallpaper is its own window (WlrLayershell keyboard focus); host only sets screen
    M_wallpaper.Popup { screen: hostScreenInfo }

    Popups.NotificationPopup {
        id: notifPopup
        screen: hostScreenInfo
        barHeight: barWindow.implicitHeight

        Component.onCompleted: Core.ModuleRegistry.registerWindowInstance("notifications", hostScreenName, this)
        Component.onDestruction: Core.ModuleRegistry.unregisterWindowInstance("notifications", hostScreenName)
    }

    Popups.OsdPopup {
        screen: hostScreenInfo
        barHeight: barWindow.implicitHeight
    }

    Popups.FingerprintPopup {
        screen: hostScreenInfo
        barHeight: barWindow.implicitHeight
        polkitActive: barWindow.polkitActive
        fingerprintMonitor: barWindow.fingerprintMonitor
    }

    PanelWindow {
        id: submapPopup
        screen: hostScreenInfo
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: submapPopupCol.width + 32
        implicitHeight: submapPopupCol.height + 16
        visible: barWindow.submapName !== ""
        color: "transparent"

        Item {
            anchors.fill: parent

            Item {
                id: submapContent
                width: parent.width
                height: parent.height
                clip: true

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: parent.height + (theme.surfaceRadius || 0)
                    color: {
                        var src = Qt.color(Helpers.Colors.submapBg);
                        var op = theme.surfaceOpacity !== undefined ? theme.surfaceOpacity : 0.8;
                        return Qt.rgba(src.r, src.g, src.b, src.a * op);
                    }
                    radius: theme.surfaceRadius || 0
                    antialiasing: true
                    layer.enabled: true
                    layer.samples: 8
                    layer.smooth: true
                }

                Column {
                    id: submapPopupCol
                    anchors.centerIn: parent
                    spacing: theme.spacingMedium || 6

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: barWindow.submapName
                        color: Helpers.Colors.submapFg
                        font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
                        font.pixelSize: barWindow.submapTitleFontSize
                        font.bold: true
                    }

                    Grid {
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: barWindow.submapBinds.length > 12 ? 3 : (barWindow.submapBinds.length > 5 ? 2 : 1)
                        rowSpacing: theme.spacingSmall || 4
                        columnSpacing: theme.spacingDefault * 2 || 16
                        flow: Grid.TopToBottom
                        rows: Math.ceil(barWindow.submapBinds.length / columns)

                        Repeater {
                            model: barWindow.submapBinds

                            Row {
                                spacing: theme.spacingDefault || 8

                                Text {
                                    width: barWindow.submapComboWidth
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.combo
                                    color: Helpers.Colors.submapFg
                                    font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
                                    font.pixelSize: barWindow.submapBindFontSize
                                    font.bold: true
                                }

                                Text {
                                    text: modelData.desc
                                    color: Helpers.Colors.textMuted
                                    font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
                                    font.pixelSize: barWindow.submapBindFontSize
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
