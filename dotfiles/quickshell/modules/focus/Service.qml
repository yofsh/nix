import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Global service: the floating focus countdown pill anchored at the bottom.
// The daemon owns completion (it fires notify-send when the timer ends), so
// this overlay is purely a live countdown plus quick pause/cancel controls.
// The pill background doubles as a progress bar (green fills as time elapses).
Item {
    id: root

    property var context: null

    property bool active: false
    property bool paused: false
    property real endAt: 0
    property int remaining: 0
    property int planned: 0
    property string label: ""

    readonly property real progress: planned > 0
        ? Math.max(0, Math.min(1, (planned - remaining) / planned)) : 0

    // Green while running, faded yellow while paused.
    readonly property color baseColor: paused ? "#e5c07b" : Helpers.Colors.accent

    // base colour with a custom alpha — keeps the palette in the theme.
    function acc(a) {
        var c = root.baseColor;
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function fmt(s) {
        s = Math.max(0, Math.round(s));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        var sec = s % 60;
        function p(n) { return (n < 10 ? "0" : "") + n; }
        if (h > 0) return h + ":" + p(m) + ":" + p(sec);
        return p(m) + ":" + p(sec);
    }

    function applyState(d) {
        if (!d || !d.active) {
            root.active = false;
            root.paused = false;
            root.remaining = 0;
            root.planned = 0;
            root.label = "";
            return;
        }
        root.active = true;
        root.paused = !!d.paused;
        root.label = d.label || "";
        root.endAt = d.endAt || 0;
        root.remaining = d.remaining || 0;
        root.planned = d.plannedSeconds || 0;
    }

    // Popup open/close/toggle IPC is provided by Core.PackagePopup.

    Helpers.DaemonFetch {
        id: stateFetch
        path: "/focus/state"
        intervalMs: 2000
        onJson: data => root.applyState(data)
    }

    Helpers.DaemonFetch {
        id: actionFetch
        onJson: data => root.applyState(data)
    }

    function action(path) {
        actionFetch.path = "/focus/" + path;
        actionFetch.reload();
    }

    Timer {
        interval: 1000
        running: root.active && !root.paused
        repeat: true
        onTriggered: {
            if (root.endAt > 0) {
                var r = Math.max(0, Math.round(root.endAt - Date.now() / 1000));
                root.remaining = r;
                if (r === 0) stateFetch.reload(); // let the daemon clear it
            }
        }
    }

    PanelWindow {
        id: overlay
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        margins.bottom: 48
        implicitWidth: pill.implicitWidth
        implicitHeight: pill.implicitHeight
        visible: root.active
        color: "transparent"

        Rectangle {
            id: pill
            implicitWidth: pillRow.implicitWidth + 20
            implicitHeight: 36
            radius: 8                       // less rounded
            clip: true
            opacity: 0.5                    // whole pill is half-transparent
            color: root.acc(0.22)           // base track (green / yellow when paused)
            border.color: root.acc(root.paused ? 0.5 : 0.85)
            border.width: 1

            // Progress fill — the background grows green as the session elapses.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.progress
                radius: parent.radius
                color: root.paused ? root.acc(0.45) : root.acc(0.90)  // accent green
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 9

                // Countdown in its own darker inset chip.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: timeText.implicitWidth + 16
                    implicitHeight: 23
                    radius: 5
                    color: Qt.darker(root.baseColor, 6)

                    Text {
                        id: timeText
                        anchors.centerIn: parent
                        text: root.fmt(root.remaining)
                        color: root.paused ? Helpers.Colors.textMuted : Helpers.Colors.textDefault
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeBody
                        font.bold: true
                    }
                }

                Text {
                    visible: root.label.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 240)
                    text: root.label
                    color: Helpers.Colors.textDefault
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) {
                    if (mouse.button === Qt.RightButton)
                        root.action("stop");
                    else
                        root.action(root.paused ? "resume" : "pause");
                }
            }
        }
    }
}
