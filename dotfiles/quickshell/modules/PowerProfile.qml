import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: profileIconText.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30

    property string profileOutput: ""

    property var profileIcons: ({
        "performance": "\uF06D",
        "balanced": "\uF24E",
        "power-saver": "\uF06C"
    })

    property string profileIcon: {
        if (!profileOutput) return "";
        return profileIcons[profileOutput] || "";
    }

    property color profileColor: {
        if (profileOutput === "performance") return "#f38ba8";
        if (profileOutput === "balanced") return "#a6e3a1";
        if (profileOutput === "power-saver") return "#89b4fa";
        return Helpers.Colors.textMuted;
    }

    property var profiles: ["power-saver", "balanced", "performance"]

    Text {
        id: profileIconText
        anchors.verticalCenter: parent.verticalCenter
        text: root.profileIcon
        color: root.profileColor
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 15
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            var idx = root.profiles.indexOf(root.profileOutput);
            var next = root.profiles[(idx + 1) % root.profiles.length];
            setProc.command = ["powerprofilesctl", "set", next];
            setProc.running = true;
        }
    }

    // Fetch profile via busctl (native C, no Python overhead)
    Process {
        id: ppProc
        command: ["busctl", "--system", "get-property",
            "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
            "net.hadess.PowerProfiles", "ActiveProfile"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                var match = text.match(/"(.+)"/);
                if (match) root.profileOutput = match[1];
            }
        }
    }

    // Monitor D-Bus for profile changes — instant updates
    Process {
        id: ppMonitor
        command: ["busctl", "--system", "--json=short", "monitor",
            "--match", "type='signal',interface='org.freedesktop.DBus.Properties',member='PropertiesChanged',path='/net/hadess/PowerProfiles'"]
        running: true
        stdout: SplitParser {
            onRead: data => ppDebounce.restart()
        }
    }

    Timer {
        id: ppDebounce
        interval: 200
        onTriggered: ppProc.running = true
    }

    Process {
        id: setProc
        command: []
        running: false
        onExited: ppProc.running = true
    }
}
