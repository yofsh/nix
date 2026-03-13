import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: row.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30
    visible: opacity > 0
    opacity: (recording || transcribing) ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

    property bool recording: false
    property bool transcribing: false
    property var spectrumLevels: new Array(24).fill(0)

    onRecordingChanged: {
        if (!recording) spectrumLevels = new Array(24).fill(0);
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            id: icon
            anchors.verticalCenter: parent.verticalCenter
            text: root.transcribing ? "" : ""
            color: root.transcribing ? "#ff9800" : Helpers.Colors.mutedRed
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 14
            Behavior on color { ColorAnimation { duration: 300 } }

            SequentialAnimation on opacity {
                running: root.transcribing
                loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
            }
        }

        Item {
            id: spectrumContainer
            width: root.recording ? spectrumRow.width : 0
            height: root.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            opacity: root.recording ? 1.0 : 0.0
            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Row {
                id: spectrumRow
                anchors.centerIn: parent
                spacing: 1

                Repeater {
                    model: 24
                    Rectangle {
                        width: 2
                        height: Math.max(2, root.spectrumLevels[index] * 14)
                        color: Helpers.Colors.mutedRed
                        radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on height { NumberAnimation { duration: 30 } }
                    }
                }
            }
        }

        Item {
            id: labelContainer
            width: root.transcribing ? labelText.implicitWidth : 0
            height: root.implicitHeight
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            opacity: root.transcribing ? 1.0 : 0.0
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.InOutQuad } }
            Behavior on opacity { NumberAnimation { duration: 300 } }

            Text {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                text: "\udb81\udd1f"
                color: "#ff9800"
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 14
            }
        }
    }

    Process {
        id: spectrumProc
        command: ["audio-spectrum"]
        running: root.recording
        stdout: SplitParser {
            onRead: data => {
                var parts = data.trim().split(" ");
                var levels = [];
                for (var i = 0; i < 24; i++)
                    levels.push(parseFloat(parts[i]) || 0);
                root.spectrumLevels = levels;
            }
        }
    }

    Process {
        id: checkProc
        command: ["bash", "-c", [
            "rec=false stt=false",
            // Check PID files and verify process is alive; clean up stale ones
            "for f in /tmp/voice_dictate.pid /tmp/voice_claude.pid /tmp/voice_stream.pid; do",
            "  [ -f \"$f\" ] || continue",
            "  if kill -0 $(head -1 \"$f\") 2>/dev/null; then rec=true",
            "  else rm \"$f\"; fi",
            "done",
            "[ -f /tmp/voice_transcribing ] && stt=true",
            "echo $rec $stt"
        ].join("\n")]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split(" ");
                root.recording = parts[0] === "true";
                root.transcribing = parts[1] === "true";
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
