import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import "../helpers" as Helpers
import "../components" as Components
import "../config" as AppConfig

PanelWindow {
    id: root
    property int barHeight: AppConfig.Config.theme.barHeight

    property bool initialized: false
    property string osdIcon: ""
    property real osdValue: 0
    property color osdColor: "white"
    property bool osdVisible: false
    property string configuredBacklightPath: AppConfig.Config.backlight.devicePath || ""
    property string backlightPath: ""

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: 200
    implicitHeight: 28
    visible: osdVisible
    color: "transparent"

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    property var sink: Pipewire.defaultAudioSink
    property int vol: sink && sink.audio ? Math.round((sink.audio.volume || 0) * 100) : 0
    property bool muted: sink && sink.audio ? sink.audio.muted : false

    onVolChanged: {
        if (!initialized) return;
        if (muted) return;
        show(volumeIcon(), vol / 100, Helpers.Colors.textDefault);
    }

    onMutedChanged: {
        if (!initialized) return;
        if (muted)
            show("\uF026", 0, Helpers.Colors.mutedRed);
        else
            show(volumeIcon(), vol / 100, Helpers.Colors.textDefault);
    }

    function volumeIcon() {
        if (muted) return "\uF026";
        if (vol > 50) return "\uF028";
        return "\uF027";
    }

    function detectBacklightPath() {
        detectBacklightProc.command = [
            "bash",
            "-lc",
            "config_path=\"$1\"\n" +
            "if [ -n \"$config_path\" ] && [ -d \"$config_path\" ]; then\n" +
            "  printf '%s' \"$config_path\"\n" +
            "elif [ -d /sys/class/backlight ]; then\n" +
            "  find /sys/class/backlight -mindepth 1 -maxdepth 1 -type d | sort | head -n1\n" +
            "fi",
            "--",
            root.configuredBacklightPath
        ];
        detectBacklightProc.running = true;
    }

    onConfiguredBacklightPathChanged: detectBacklightPath()

    FileView {
        id: brightnessFile
        path: root.backlightPath ? root.backlightPath + "/brightness" : ""
        blockLoading: true
        watchChanges: true
        onFileChanged: this.reload()
    }

    FileView {
        id: maxBrightnessFile
        path: root.backlightPath ? root.backlightPath + "/max_brightness" : ""
        blockLoading: true
    }

    property int brightnessPct: {
        var cur = parseInt(brightnessFile.text().trim()) || 0;
        var max = parseInt(maxBrightnessFile.text().trim()) || 1;
        return max > 0 ? Math.round(cur / max * 100) : 0;
    }

    property int lastBrightness: -1

    onBrightnessPctChanged: {
        if (lastBrightness < 0) {
            lastBrightness = brightnessPct;
            return;
        }
        if (brightnessPct === lastBrightness) return;
        lastBrightness = brightnessPct;
        if (!initialized) return;
        show("\uF185", brightnessPct / 100, Helpers.Colors.backlight);
    }

    Timer {
        interval: 500
        running: true
        onTriggered: root.initialized = true
    }

    Process {
        id: detectBacklightProc
        command: []
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.backlightPath = this.text.trim();
                brightnessFile.reload();
                maxBrightnessFile.reload();
            }
        }
    }

    function show(icon, value, clr) {
        osdIcon = icon;
        osdValue = Math.max(0, Math.min(1, value));
        osdColor = clr;
        osdVisible = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.osdVisible = false
    }

    Item {
        anchors.fill: parent

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            opacity: AppConfig.Config.theme.surfaceOpacity

            Components.PopupSurface {
                anchors.fill: parent
            }

            Row {
                anchors.centerIn: parent
                spacing: AppConfig.Config.theme.spacingDefault

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.osdIcon
                    color: root.osdColor
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeIcon
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 120
                    height: 6

                    Rectangle {
                        anchors.fill: parent
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.15)
                    }

                    Rectangle {
                        width: parent.width * root.osdValue
                        height: parent.height
                        radius: 3
                        color: root.osdColor

                        Behavior on width {
                            NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(root.osdValue * 100)
                    color: root.osdColor
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeDefault
                }
            }
        }
    }

    Component.onCompleted: detectBacklightPath()
}
