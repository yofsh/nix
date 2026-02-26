import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: iconText.implicitWidth + artWrapper.width + infoWrapper.width + 4
    implicitHeight: parent ? parent.height : 30
    visible: root.player !== null
    clip: true

    property MprisPlayer player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    property bool hovered: false
    property real progress: (player && player.positionSupported && player.lengthSupported && player.length > 0)
        ? Math.max(0, Math.min(1, player.position / player.length)) : -1

    Timer {
        interval: 1000
        running: root.player !== null && root.player.isPlaying
        repeat: true
        onTriggered: root.progressChanged()
    }

    property string displayText: {
        if (!player) return "";
        return player.isPlaying ? " 󰏤 " : " 󰐊 ";
    }

    property string trackInfo: {
        if (!player) return "";
        var parts = [];
        if (player.trackArtist) parts.push(player.trackArtist);
        if (player.trackTitle) parts.push(player.trackTitle);
        return parts.join(" - ");
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.progress >= 0 ? Qt.rgba(1, 1, 1, 0.08) : (root.hovered ? Qt.rgba(0.047, 0.686, 0.286, 0.15) : "transparent")
        clip: true

        Behavior on color {
            ColorAnimation { duration: 200 }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: root.progress >= 0 ? parent.width * root.progress : 0
            radius: parent.radius
            color: Qt.rgba(0.047, 0.686, 0.286, 0.25)
            visible: root.progress >= 0

            Behavior on width {
                NumberAnimation { duration: 200 }
            }
        }
    }

    property string artUrl: player && player.trackArtUrl ? player.trackArtUrl : ""

    // Hidden text to measure target width without binding loop
    Text {
        id: infoMeasure
        text: root.trackInfo
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 12
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
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 15
        }

        Item {
            id: artWrapper
            anchors.verticalCenter: parent.verticalCenter
            height: root.implicitHeight
            width: root.hovered && root.artUrl !== "" ? height : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Image {
                id: artImage
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
            width: root.hovered ? infoMeasure.implicitWidth + 4 : 0
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
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 12
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        property real _scrollAccum: 0

        onEntered: root.hovered = true
        onExited: root.hovered = false

        onClicked: function(mouse) {
            if (!root.player) return;
            if (mouse.button === Qt.LeftButton) {
                root.player.togglePlaying();
            } else if (mouse.button === Qt.RightButton) {
                root.player.next();
            } else if (mouse.button === Qt.MiddleButton) {
                var q = root.player.trackArtist + " - " + root.player.trackTitle;
                geniusProc.command = ["xdg-open", "https://genius.com/search?q=" + encodeURIComponent(q)];
                geniusProc.running = true;
            }
        }

        onWheel: function(wheel) {
            if (!root.player || !root.player.canSeek) return;
            _scrollAccum += wheel.angleDelta.y;
            if (Math.abs(_scrollAccum) < 120) return;
            if (_scrollAccum > 0)
                root.player.seek(3);
            else
                root.player.seek(-3);
            _scrollAccum = 0;
        }
    }

    Process {
        id: geniusProc
        command: []
        running: false
    }
}
