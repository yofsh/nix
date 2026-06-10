import QtQuick
import Quickshell.Io
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// GPU load, mirroring the cpu widget: a mini history graph with the load %
// overlaid. Fed by the `gpu-load` helper (NVIDIA/AMD/Intel, auto-detected).
// Stays collapsed/hidden on hosts with no supported GPU — the helper simply
// produces no output there, so `available` never flips true.
Item {
    id: root
    property var context: null
    property var config: Helpers.ModuleConfig.resolve("gpu")

    property bool available: false
    property int usagePercent: 0
    property int memPercent: 0

    // History for graph (load %).
    property int maxHistory: 60
    property var history: []

    readonly property int intervalSeconds: Math.max(1, Math.round(config.intervalMs / 1000))

    visible: available
    implicitWidth: available ? graphCanvas.width : 0
    implicitHeight: parent ? parent.height : 30

    Canvas {
        id: graphCanvas
        width: root.maxHistory
        height: root.implicitHeight
        anchors.verticalCenter: parent.verticalCenter

        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var h = root.history;
            if (h.length === 0) return;
            var offset = width - h.length;

            ctx.beginPath();
            ctx.moveTo(offset, height);
            for (var i = 0; i < h.length; i++) {
                var y = height - (h[i] / 100) * height;
                ctx.lineTo(offset + i, y);
                ctx.lineTo(offset + i + 1, y);
            }
            ctx.lineTo(offset + h.length, height);
            ctx.closePath();
            ctx.fillStyle = Helpers.Colors.gpu;
            ctx.fill();
        }
    }

    // Overlay on the left of the chart: GPU load, then VRAM usage to its right
    // in a distinct color. The icon is dropped in favour of the load number.
    Row {
        anchors.left: graphCanvas.left
        anchors.leftMargin: 2
        anchors.top: graphCanvas.top
        anchors.topMargin: 1
        spacing: 3
        z: 1

        Components.ThemedText {
            text: root.usagePercent
            color: AppConfig.Config.gpu.usageColor
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }

        Components.ThemedText {
            text: root.memPercent
            color: AppConfig.Config.gpu.memColor
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }
    }

    function pushSample(load) {
        root.usagePercent = load;
        var h = root.history.slice();
        h.push(load);
        if (h.length > root.maxHistory)
            h.shift();
        root.history = h;
        graphCanvas.requestPaint();
    }

    // Single long-lived helper process streams "<load> <mem>" per sample —
    // no per-tick spawn. Auto-restarts if it ever exits.
    Process {
        id: gpuProc
        command: ["gpu-load", String(root.intervalSeconds)]
        running: true

        stdout: SplitParser {
            onRead: line => {
                var parts = line.trim().split(/\s+/);
                if (parts.length < 1 || parts[0] === "") return;
                var load = parseInt(parts[0]);
                if (isNaN(load)) return;
                root.memPercent = parseInt(parts[1]) || 0;
                root.available = true;
                root.pushSample(Math.max(0, Math.min(100, load)));
            }
        }

        // If the helper dies (e.g. driver hiccup), retry after one interval.
        onExited: restartTimer.start()
    }

    Timer {
        id: restartTimer
        interval: root.intervalSeconds * 1000
        repeat: false
        onTriggered: gpuProc.running = true
    }
}
