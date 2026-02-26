import QtQuick
import Quickshell
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: visible ? row.implicitWidth + 8 : 0
    implicitHeight: parent ? parent.height : 30
    visible: jobCount > 0 || showCompleted

    property int jobCount: 0
    property int elapsed: 0
    property var knownActiveIds: []
    property var completionTimes: []
    property int recentCompletedCount: 0
    property bool showCompleted: false
    property bool hovered: false
    property string activeTitle: ""

    readonly property string xdgDataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
    readonly property string processingPath: xdgDataHome + "/yts/_processing.json"

    Component.onCompleted: root.parseStatus()

    function parseStatus() {
        var text = statusFile.text();
        var currentActiveIds = [];

        if (text && text.trim() !== "") {
            try {
                var data = JSON.parse(text);
                var items = data.items || [];
                var active = items.filter(function(it) { return it.stage !== "error"; });
                root.jobCount = active.length;
                currentActiveIds = active.map(function(it) { return it.videoId; });
                root.activeTitle = active.length > 0 ? (active[0].title || "") : "";

                if (active.length > 0 && active[0].startedAt) {
                    var start = new Date(active[0].startedAt).getTime();
                    root.elapsed = Math.floor((Date.now() - start) / 1000);
                }
            } catch(e) {
                root.jobCount = 0;
            }
        } else {
            root.jobCount = 0;
        }

        // Detect newly completed: IDs that were active but are now gone
        if (root.knownActiveIds.length > 0) {
            var now = Date.now();
            var newCompletions = [];
            for (var i = 0; i < root.knownActiveIds.length; i++) {
                if (currentActiveIds.indexOf(root.knownActiveIds[i]) === -1) {
                    newCompletions.push(now);
                }
            }
            if (newCompletions.length > 0) {
                root.completionTimes = root.completionTimes.concat(newCompletions);
            }
        }
        root.knownActiveIds = currentActiveIds;
        updateCompletedState();
    }

    function updateCompletedState() {
        var now = Date.now();
        var fiveMinAgo = now - 5 * 60 * 1000;
        root.completionTimes = root.completionTimes.filter(function(t) { return t > fiveMinAgo; });
        root.recentCompletedCount = root.completionTimes.length;

        if (root.jobCount === 0 && root.recentCompletedCount > 0) {
            root.showCompleted = true;
            hideTimer.restart();
        } else if (root.jobCount > 0) {
            root.showCompleted = false;
            hideTimer.stop();
        }
    }

    function formatTime(secs) {
        var m = Math.floor(secs / 60);
        var s = secs % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    FileView {
        id: statusFile
        path: root.processingPath
        blockLoading: true
        watchChanges: true
        onFileChanged: {
            this.reload();
            root.parseStatus();
        }
    }

    // Tick elapsed counter and re-read file every second while jobs are active
    Timer {
        interval: 1000
        running: root.jobCount > 0
        repeat: true
        onTriggered: {
            statusFile.reload();
            root.parseStatus();
        }
    }

    // Hide completed indicator 60s after last job finished
    Timer {
        id: hideTimer
        interval: 60000
        running: false
        repeat: false
        onTriggered: {
            if (root.jobCount === 0) {
                root.showCompleted = false;
            }
        }
    }

    // Periodically prune old completions (>5min) while showing completed state
    Timer {
        interval: 60000
        running: root.showCompleted
        repeat: true
        onTriggered: root.updateCompletedState()
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.showCompleted && root.jobCount === 0 ? "\uf00c" : "\uf16a"
            color: root.showCompleted && root.jobCount === 0 ? "#50fa7b" : "#ff0000"
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (root.showCompleted && root.jobCount === 0)
                    return root.recentCompletedCount.toString();
                var t = root.formatTime(root.elapsed);
                if (root.jobCount > 1)
                    return root.jobCount + " " + t;
                return t;
            }
            color: root.showCompleted && root.jobCount === 0 ? "#50fa7b" : Helpers.Colors.textDefault
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 10
        }

        // Hover-expanding video title
        Item {
            id: titleWrapper
            anchors.verticalCenter: parent.verticalCenter
            height: titleText.implicitHeight
            width: root.hovered && root.activeTitle ? titleText.implicitWidth + 4 : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Text {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 4
                text: root.activeTitle
                color: Helpers.Colors.textMuted
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 10
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onClicked: listProc.running = true
    }

    Process {
        id: listProc
        command: ["hyprctl", "dispatch", "exec", "[float; size 1400 (monitor_h*0.8); center] foot -e yts list"]
        running: false
    }
}
