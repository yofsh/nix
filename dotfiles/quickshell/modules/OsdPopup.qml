import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import "../helpers" as Helpers

PanelWindow {
    id: root
    property int barHeight: 22

    property bool initialized: false
    property string osdIcon: ""
    property real osdValue: 0
    property color osdColor: "white"
    property bool osdVisible: false

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: 200
    implicitHeight: 28
    visible: osdVisible || slideAnim.running
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

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        blockLoading: true
        watchChanges: true
        onFileChanged: this.reload()
    }

    FileView {
        id: maxBrightnessFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
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
        clip: true

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            y: -parent.height
            opacity: 0.8

            states: State {
                name: "visible"; when: root.osdVisible
                PropertyChanges { target: popupContent; y: 0 }
            }

            transitions: Transition {
                id: slideAnim
                NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic }
            }

            Item {
                anchors.fill: parent
                clip: true

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: -16
                    color: "#11000000"
                    radius: 16
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.osdIcon
                    color: root.osdColor
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 14
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
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 12
                }
            }
        }
    }
}
