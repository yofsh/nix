import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: volRow.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    property var sink: Pipewire.defaultAudioSink
    property var source: Pipewire.defaultAudioSource

    property bool isMuted: sink && sink.audio ? sink.audio.muted : false
    property int vol: sink && sink.audio ? Math.round((sink.audio.volume || 0) * 100) : 0
    property bool sourceMuted: source && source.audio ? source.audio.muted : false
    property bool isBluetooth: sink ? (sink.name || "").indexOf("bluez") >= 0 : false

    function volumeIcon() {
        if (root.isMuted) return "\uF026";                               // nf-fa-volume_off
        if (root.isBluetooth) return "\uF293";                           // nf-fa-bluetooth
        if (root.vol > 50) return "\uF028";                              // nf-fa-volume_up
        return "\uF027";                                                 // nf-fa-volume_down
    }

    function micIcon() {
        if (root.sourceMuted) return "\uF131";                           // nf-fa-microphone_slash
        return "";
    }

    Row {
        id: volRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.isMuted
            text: root.vol + ""
            color: Helpers.Colors.textDefault
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.volumeIcon()
            color: root.isMuted ? Helpers.Colors.mutedRed : Helpers.Colors.textDefault
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 14
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.micIcon()
            color: root.sourceMuted ? Helpers.Colors.mutedRed : Helpers.Colors.textDefault
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 13
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        property real _scrollAccum: 0
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                pavuProc.running = true;
            } else if (mouse.button === Qt.RightButton) {
                btProc.running = true;
            }
        }
        onWheel: function(wheel) {
            _scrollAccum += wheel.angleDelta.y;
            if (Math.abs(_scrollAccum) < 120) return;
            if (_scrollAccum > 0)
                volChangeProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%+"];
            else
                volChangeProc.command = ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"];
            _scrollAccum = 0;
            volChangeProc.running = true;
        }
    }

    Process {
        id: volChangeProc
        command: []
        running: false
    }

    Process {
        id: pavuProc
        command: ["hyprctl", "dispatch", "togglespecialworkspace", "audio"]
        running: false
    }

    Process {
        id: btProc
        command: ["bash", "-c", "bt-audio-status toggle &> /dev/null"]
        running: false
    }
}
