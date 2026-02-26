import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: memColumn.width + 4
    implicitHeight: parent ? parent.height : 30

    property int memPct: 0
    property int swapPct: 0

    function parseMem() {
        var text = memFile.text();
        if (!text) return;

        var vals = {};
        var lines = text.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split(/\s+/);
            if (parts.length >= 2) vals[parts[0]] = parseInt(parts[1]);
        }

        var total = vals["MemTotal:"] || 0;
        var avail = vals["MemAvailable:"] || 0;
        var swapTotal = vals["SwapTotal:"] || 0;
        var swapFree = vals["SwapFree:"] || 0;

        if (total > 0)
            root.memPct = Math.round((1 - avail / total) * 100);
        root.swapPct = swapTotal > 0 ? Math.round((1 - swapFree / swapTotal) * 100) : 0;
    }

    Column {
        id: memColumn
        anchors.verticalCenter: parent.verticalCenter
        spacing: -2
        width: Math.max(memText.implicitWidth, swapText.implicitWidth)

        Text {
            id: memText
            text: root.memPct
            color: Helpers.Colors.memory
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 10
        }

        Text {
            id: swapText
            text: root.swapPct
            color: "#a5d6a7"
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 10
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        blockLoading: true
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            memFile.reload();
            root.parseMem();
        }
    }

    Component.onCompleted: root.parseMem()
}
