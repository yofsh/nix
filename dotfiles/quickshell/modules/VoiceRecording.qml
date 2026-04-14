import QtQuick
import Quickshell.Io
import "../helpers" as Helpers
import "../config" as AppConfig

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
            color: root.transcribing ? Helpers.Colors.cpu : Helpers.Colors.mutedRed
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon
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
                color: Helpers.Colors.cpu
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeIcon
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: cancelProc.running = true
    }

    Process {
        id: cancelProc
        command: ["bash", "-c", [
            "for mode in dictate claude; do",
            "  pf=\"/tmp/voice_${mode}.pid\"",
            "  [ -f \"$pf\" ] || continue",
            "  pid=$(head -1 \"$pf\")",
            "  kill \"$pid\" 2>/dev/null",
            "  rm -f \"$pf\" \"/tmp/voice_${mode}.wav\"",
            "done",
            "spf=/tmp/voice_stream.pid",
            "if [ -f \"$spf\" ]; then",
            "  IFS=: read sp pp < \"$spf\"",
            "  kill \"$sp\" \"$pp\" 2>/dev/null",
            "  rm -f \"$spf\" /tmp/voice_stream.fifo",
            "fi",
            "rm -f /tmp/voice_transcribing"
        ].join("\n")]
        running: false
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
            "for f in '" + AppConfig.Config.voice.dictatePidFile + "' '" + AppConfig.Config.voice.claudePidFile + "' '" + AppConfig.Config.voice.streamPidFile + "'; do",
            "  [ -f \"$f\" ] || continue",
            "  if kill -0 $(head -1 \"$f\") 2>/dev/null; then rec=true",
            "  else rm \"$f\"; fi",
            "done",
            "[ -f '" + AppConfig.Config.voice.transcribingFlag + "' ] && stt=true",
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
