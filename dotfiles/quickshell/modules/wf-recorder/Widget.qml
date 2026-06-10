import QtQuick
import Quickshell.Io
import "../../components" as Components
import "../../helpers" as Helpers

Item {
    id: root
    implicitWidth: visible ? recText.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 30
    visible: recOutput !== ""

    property string recOutput: ""

    Components.ThemedText {
        id: recText
        anchors.verticalCenter: parent.verticalCenter
        text: " ● "
        color: Helpers.Colors.mutedRed
        font.pixelSize: 12
    }

    Process {
        id: recProc
        command: ["pgrep", "wf-recorder"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.recOutput = this.text.trim()
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: recProc.running = true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            screenrecProc.running = true;
        }
    }

    Process {
        id: screenrecProc
        command: ["screencast"]
        running: false
    }
}
