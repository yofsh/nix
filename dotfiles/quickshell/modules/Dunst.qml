import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: dunstText.implicitWidth + 12
    implicitHeight: parent ? parent.height : 30

    property bool paused: false
    property int waitingCount: 0

    property string displayText: {
        if (!paused) return "󰂚";
        return waitingCount > 0 ? "󰵙 " + waitingCount : "󰂞";
    }

    Text {
        id: dunstText
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: Helpers.Colors.textDefault
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 14
    }

    // Long-running D-Bus monitor — emits JSON on every dunst property change
    Process {
        id: dbusMonitor
        command: ["busctl", "--user", "--json=short", "monitor",
                  "--match", "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/org/freedesktop/Notifications'"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                try {
                    var msg = JSON.parse(data);
                    var props = msg.payload?.data?.[1] || {};
                    if ("paused" in props)
                        root.paused = props.paused.data;
                    if ("waitingLength" in props)
                        root.waitingCount = props.waitingLength.data;
                } catch(e) {}
            }
        }
    }

    // Initial state fetch
    Process {
        id: pausedProc
        command: ["dunstctl", "is-paused"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.paused = this.text.trim() === "true"
        }
    }

    Process {
        id: countProc
        command: ["dunstctl", "count", "waiting"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.waitingCount = parseInt(this.text.trim()) || 0
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: toggleProc.running = true
    }

    Process {
        id: toggleProc
        command: ["dunstctl", "set-paused", "toggle"]
        running: false
    }
}
