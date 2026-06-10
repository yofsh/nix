import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: row.implicitWidth + 8
    implicitHeight: parent ? parent.height : 26

    property var context: null
    property bool popupOpen: false

    // -- focus state (mirrored from the daemon) --
    property bool active: false
    property bool paused: false
    property real endAt: 0          // epoch seconds
    property int remaining: 0       // seconds
    property string label: ""

    readonly property color idleColor: Helpers.Colors.textMuted
    readonly property color runColor: Helpers.Colors.accent

    function fmt(s) {
        s = Math.max(0, Math.round(s));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        var sec = s % 60;
        function p(n) { return (n < 10 ? "0" : "") + n; }
        if (h > 0) return h + ":" + p(m) + ":" + p(sec);
        return m + ":" + p(sec);
    }

    function applyState(d) {
        if (!d || !d.active) {
            root.active = false;
            root.paused = false;
            root.remaining = 0;
            root.label = "";
            return;
        }
        root.active = true;
        root.paused = !!d.paused;
        root.label = d.label || "";
        root.endAt = d.endAt || 0;
        root.remaining = d.remaining || 0;
    }

    // Poll the daemon so changes from elsewhere (popup, overlay) are reflected.
    Helpers.DaemonFetch {
        path: "/focus/state"
        intervalMs: 2000
        onJson: d => root.applyState(d)
    }

    // Local 1s tick keeps the countdown smooth between polls.
    Timer {
        interval: 1000
        running: root.active && !root.paused
        repeat: true
        onTriggered: {
            if (root.endAt > 0)
                root.remaining = Math.max(0, Math.round(root.endAt - Date.now() / 1000));
        }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Components.ThemedText {
            anchors.verticalCenter: parent.verticalCenter
            text: root.paused ? "" : ""   // pause / clock glyphs
            color: root.active ? root.runColor : root.idleColor
            font.pixelSize: AppConfig.Config.theme.fontSizeDefault
        }

    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.popupOpen = !root.popupOpen
    }
}
