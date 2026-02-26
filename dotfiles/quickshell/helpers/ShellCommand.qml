import QtQuick
import Quickshell.Io

Item {
    id: root
    width: 0; height: 0; visible: false

    property list<string> command: []
    property int interval: 2000
    property string output: ""

    function refresh() {
        proc.running = true;
    }

    Process {
        id: proc
        command: root.command
        running: root.command.length > 0

        stdout: StdioCollector {
            onStreamFinished: {
                root.output = this.text.trim();
            }
        }
    }

    Timer {
        interval: root.interval
        running: root.command.length > 0
        repeat: true
        onTriggered: proc.running = true
    }
}
