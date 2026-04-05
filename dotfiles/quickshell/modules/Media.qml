import QtQuick
import Quickshell.Io
import "../helpers" as Helpers
import "../config" as AppConfig

Item {
    id: root
    implicitWidth: iconText.implicitWidth + artWrapper.width + infoWrapper.width
    implicitHeight: parent ? parent.height : 30
    visible: root.playerName !== ""
    clip: true

    property string playerName: ""
    property string playStatus: ""
    property string trackArtist: ""
    property string trackTitle: ""
    property string artUrl: ""
    property int trackLengthMicros: 0
    property real trackPositionSeconds: 0
    property bool hovered: false
    property bool expanded: false
    property bool isPlaying: root.playStatus === "Playing"
    property real progress: root.trackLengthMicros > 0
        ? Math.max(0, Math.min(1, (root.trackPositionSeconds * 1000000) / root.trackLengthMicros)) : -1

    function clearPlayer() {
        root.playerName = "";
        root.playStatus = "";
        root.trackArtist = "";
        root.trackTitle = "";
        root.artUrl = "";
        root.trackLengthMicros = 0;
        root.trackPositionSeconds = 0;
        root.hovered = false;
    }

    function refresh() {
        if (!infoProc.running)
            infoProc.running = true;
    }

    Timer {
        interval: root.playerName !== "" ? 1000 : 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    Timer {
        id: refreshDelay
        interval: 150
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    property string displayText: {
        if (!root.playerName) return "";
        return root.isPlaying ? " " + String.fromCodePoint(0xF03E4) + " " : " " + String.fromCodePoint(0xF040A) + " ";
    }

    property string trackInfo: {
        var parts = [];
        if (root.trackArtist) parts.push(root.trackArtist);
        if (root.trackTitle) parts.push(root.trackTitle);
        return parts.join(" - ");
    }

    Rectangle {
        anchors.fill: parent
        radius: 0
        color: root.progress >= 0 ? Qt.rgba(1, 1, 1, 0.08) : (root.expanded ? Qt.rgba(0.047, 0.686, 0.286, 0.15) : "transparent")
        clip: true

        Behavior on color {
            ColorAnimation { duration: 200 }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.progress >= 0 ? parent.width * root.progress : 0
            radius: 0
            color: Qt.rgba(0.047, 0.686, 0.286, 0.25)
            visible: root.progress >= 0

            Behavior on width {
                NumberAnimation { duration: 200 }
            }
        }
    }

    Text {
        id: infoMeasure
        text: root.trackInfo
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeDefault
        visible: false
    }

    Row {
        id: mediaRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
            id: iconText
            anchors.verticalCenter: parent.verticalCenter
            text: root.displayText
            color: Helpers.Colors.media
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: 15
        }

        Item {
            id: artWrapper
            anchors.verticalCenter: parent.verticalCenter
            height: root.implicitHeight
            width: root.expanded && root.artUrl !== "" ? height : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Image {
                source: root.artUrl
                width: parent.height
                height: parent.height
                fillMode: Image.PreserveAspectCrop
                smooth: true
            }
        }

        Item {
            id: infoWrapper
            anchors.verticalCenter: parent.verticalCenter
            height: infoText.implicitHeight
            width: root.expanded ? infoMeasure.implicitWidth + 4 : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Text {
                id: infoText
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 4
                text: root.trackInfo
                color: Helpers.Colors.media
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeDefault
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        property real scrollAccum: 0

        onEntered: { root.hovered = true; hoverDelay.restart() }
        onExited: { root.hovered = false; hoverDelay.stop(); root.expanded = false }

        onClicked: function(mouse) {
            if (!root.playerName) return;
            if (mouse.button === Qt.LeftButton) {
                controlProc.command = ["playerctl", "-s", "-p", root.playerName, "play-pause"];
                controlProc.running = true;
            } else if (mouse.button === Qt.RightButton) {
                controlProc.command = ["playerctl", "-s", "-p", root.playerName, "next"];
                controlProc.running = true;
            } else if (mouse.button === Qt.MiddleButton) {
                var q = root.trackArtist + " - " + root.trackTitle;
                geniusProc.command = ["xdg-open", "https://genius.com/search?q=" + encodeURIComponent(q)];
                geniusProc.running = true;
            }
        }

        onWheel: function(wheel) {
            if (!root.playerName || root.trackLengthMicros <= 0) return;
            scrollAccum += wheel.angleDelta.y;
            if (Math.abs(scrollAccum) < 120) return;
            controlProc.command = ["playerctl", "-s", "-p", root.playerName, "position", scrollAccum > 0 ? "3+" : "3-"];
            scrollAccum = 0;
            controlProc.running = true;
        }
    }

    Timer {
        id: hoverDelay
        interval: 400
        onTriggered: if (root.hovered) root.expanded = true
    }

    Process {
        id: infoProc
        command: ["bash", "-c", [
            "PLAYER=$(playerctl -s -l 2>/dev/null | grep -v '^playerctld$' | head -n 1)",
            "[ -n \"$PLAYER\" ] || exit 0",
            "STATUS=$(playerctl -s -p \"$PLAYER\" status 2>/dev/null || true)",
            "ARTIST=$(playerctl -s -p \"$PLAYER\" metadata --format '{{artist}}' 2>/dev/null || true)",
            "TITLE=$(playerctl -s -p \"$PLAYER\" metadata --format '{{title}}' 2>/dev/null || true)",
            "ART=$(playerctl -s -p \"$PLAYER\" metadata --format '{{mpris:artUrl}}' 2>/dev/null || true)",
            "LEN=$(playerctl -s -p \"$PLAYER\" metadata --format '{{mpris:length}}' 2>/dev/null || true)",
            "POS=$(playerctl -s -p \"$PLAYER\" position 2>/dev/null || true)",
            "printf '%s\\n%s\\n%s\\n%s\\n%s\\n%s\\n%s\\n' \"$PLAYER\" \"$STATUS\" \"$ARTIST\" \"$TITLE\" \"$ART\" \"$LEN\" \"$POS\""
        ].join("\n")]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                if (lines.length < 7 || lines[0].trim() === "") {
                    root.clearPlayer();
                    return;
                }
                root.playerName = lines[0].trim();
                root.playStatus = lines[1].trim();
                root.trackArtist = lines[2].trim();
                root.trackTitle = lines[3].trim();
                root.artUrl = lines[4].trim();
                root.trackLengthMicros = parseInt(lines[5].trim()) || 0;
                root.trackPositionSeconds = parseFloat(lines[6].trim()) || 0;
            }
        }
    }

    Process {
        id: controlProc
        command: []
        running: false
        onExited: refreshDelay.restart()
    }

    Process {
        id: geniusProc
        command: []
        running: false
    }
}
