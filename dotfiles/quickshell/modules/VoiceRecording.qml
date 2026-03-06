import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: visible ? row.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 30
    visible: recording || transcribing

    property bool recording: false
    property bool transcribing: false

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            text: root.transcribing ? "󰗋" : ""
            color: root.transcribing ? "#ff9800" : Helpers.Colors.mutedRed
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 14

            SequentialAnimation on opacity {
                running: root.visible
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.transcribing ? "STT" : "REC"
            color: root.transcribing ? "#ff9800" : Helpers.Colors.mutedRed
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }
    }

    Process {
        id: checkProc
        command: ["bash", "-c", "echo rec:$(ls /tmp/voice_*.pid 2>/dev/null) stt:$(ls /tmp/voice_transcribing 2>/dev/null)"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var out = this.text.trim();
                root.recording = out.indexOf("rec:/tmp/") >= 0;
                root.transcribing = out.indexOf("stt:/tmp/") >= 0;
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: checkProc.running = true
    }
}
