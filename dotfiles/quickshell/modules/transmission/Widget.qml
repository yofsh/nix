import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: visible ? row.implicitWidth + 8 : 0
    implicitHeight: parent ? parent.height : 30
    visible: activeCount > 0

    property var context: null
    property var config: Helpers.ModuleConfig.resolve("transmission")

    property int activeCount: 0
    property real totalDownKBs: 0      // KB/s, transmission decimal kilo
    property real dominantPercent: 0
    property string dominantEta: ""

    function formatSpeed(kbs) {
        if (kbs >= 1000)
            return (kbs / 1000).toFixed(1) + " MB/s";
        return Math.round(kbs) + " KB/s";
    }

    function parseListing(text) {
        if (!text) { root.activeCount = 0; return; }
        var lines = text.split("\n");
        var active = 0;
        var total = 0;
        var bestRate = -1;
        var bestPct = 0;
        var bestEta = "";

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var statusIdx = -1;
            if (line.indexOf(" Downloading ") >= 0)
                statusIdx = line.indexOf(" Downloading ");
            else if (line.indexOf(" Up & Down ") >= 0)
                statusIdx = line.indexOf(" Up & Down ");
            if (statusIdx < 0) continue;

            var pre = line.substring(0, statusIdx).trim();
            var tokens = pre.split(/\s+/);
            // [id, pct, sizeNum, sizeUnit, eta..., up, down, ratio]
            if (tokens.length < 7) continue;

            var down = parseFloat(tokens[tokens.length - 2]);
            if (isNaN(down)) down = 0;
            var pct = parseFloat(tokens[1]);
            if (isNaN(pct)) pct = 0;
            var eta = tokens.slice(4, tokens.length - 3).join(" ");

            active += 1;
            total += down;
            if (down > bestRate) {
                bestRate = down;
                bestPct = pct;
                bestEta = eta;
            }
        }

        root.activeCount = active;
        root.totalDownKBs = total;
        root.dominantPercent = bestPct;
        root.dominantEta = bestEta;
    }

    Process {
        id: listProc
        command: ["transmission-remote", "-l"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseListing(this.text)
        }
    }

    Timer {
        interval: root.config.intervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!listProc.running) listProc.running = true; }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ""  // nf-fa-download
            color: AppConfig.Config.theme.colors.accent
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.formatSpeed(root.totalDownKBs)
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.dominantPercent.toFixed(root.dominantPercent >= 10 ? 0 : 1) + "%"
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.dominantEta !== "" && root.dominantEta !== "Done" && root.dominantEta !== "Unknown"
            text: root.dominantEta
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.activeCount > 1
            text: "(" + root.activeCount + ")"
            color: Helpers.Colors.textMuted
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: openProc.running = true
    }

    Process {
        id: openProc
        command: ["hyprctl", "dispatch", "exec", "[float; size 1200 600; center] foot -e zsh -c 'watch -n 2 transmission-remote -l; exec zsh'"]
        running: false
    }
}
