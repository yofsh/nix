import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: graphCanvas.width
    implicitHeight: parent ? parent.height : 30

    // Previous CPU stats for delta calculation
    property var prevUser: 0
    property var prevSystem: 0
    property var prevTotal: 0
    property int usagePercent: 0
    property int userPercent: 0
    property int systemPercent: 0

    // History for graph (60 samples = 60 seconds at 1s interval)
    // Each entry: {user: %, sys: %}
    property int maxHistory: 60
    property var history: []

    property string currentFreq: ""

    // Power profile
    property string profileOutput: ""

    property color profileColor: {
        if (profileOutput === "performance") return AppConfig.Config.cpu.performanceColor;
        if (profileOutput === "balanced") return AppConfig.Config.cpu.balancedColor;
        if (profileOutput === "power-saver") return AppConfig.Config.cpu.powerSaverColor;
        return Helpers.Colors.textMuted;
    }

    property var profiles: ["power-saver", "balanced", "performance"]

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

            // Draw system (orange) as filled area with rectangular steps
            ctx.beginPath();
            ctx.moveTo(offset, height);
            for (var i = 0; i < h.length; i++) {
                var sysH = (h[i].sys / 100) * height;
                ctx.lineTo(offset + i, height - sysH);
                ctx.lineTo(offset + i + 1, height - sysH);
            }
            ctx.lineTo(offset + h.length, height);
            ctx.closePath();
            ctx.fillStyle = Helpers.Colors.cpu;
            ctx.fill();

            // Draw user (green) stacked on top of system with rectangular steps
            ctx.beginPath();
            // Top edge: user+sys line (left to right)
            for (var i = 0; i < h.length; i++) {
                var sysH2 = (h[i].sys / 100) * height;
                var userH = (h[i].user / 100) * height;
                if (i === 0) ctx.moveTo(offset, height - sysH2 - userH);
                else ctx.lineTo(offset + i, height - sysH2 - userH);
                ctx.lineTo(offset + i + 1, height - sysH2 - userH);
            }
            // Bottom edge: sys line (right to left)
            for (var j = h.length - 1; j >= 0; j--) {
                var sysH3 = (h[j].sys / 100) * height;
                ctx.lineTo(offset + j + 1, height - sysH3);
                ctx.lineTo(offset + j, height - sysH3);
            }
            ctx.closePath();
            ctx.fillStyle = Helpers.Colors.cpuUser;
            ctx.fill();
        }
    }

    // Overlay: freq and load on the left of the chart
    Column {
        id: cpuOverlay
        anchors.left: graphCanvas.left
        anchors.leftMargin: 2
        anchors.verticalCenter: graphCanvas.verticalCenter
        spacing: -2
        z: 1

        Text {
            text: root.currentFreq
            color: root.profileColor
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }

        Text {
            text: root.usagePercent
            color: AppConfig.Config.cpu.usageColor
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }
    }

    // Click chart to cycle power profile
    MouseArea {
        anchors.fill: graphCanvas
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            var idx = root.profiles.indexOf(root.profileOutput);
            var next = root.profiles[(idx + 1) % root.profiles.length];
            setProc.command = ["busctl", "--system", "set-property",
                "net.hadess.PowerProfiles", "/net/hadess/PowerProfiles",
                "net.hadess.PowerProfiles", "ActiveProfile", "s", next];
            setProc.running = true;
        }
    }

    // Max frequency across all cores via sysfs FileViews — zero process spawns
    FileView { id: freq0; path: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"; blockLoading: true }
    FileView { id: freq1; path: "/sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq"; blockLoading: true }
    FileView { id: freq2; path: "/sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq"; blockLoading: true }
    FileView { id: freq3; path: "/sys/devices/system/cpu/cpu3/cpufreq/scaling_cur_freq"; blockLoading: true }
    FileView { id: freq4; path: "/sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq"; blockLoading: true }
    FileView { id: freq5; path: "/sys/devices/system/cpu/cpu5/cpufreq/scaling_cur_freq"; blockLoading: true }
    FileView { id: freq6; path: "/sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq"; blockLoading: true }
    FileView { id: freq7; path: "/sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq"; blockLoading: true }

    function parseFreq() {
        var views = [freq0, freq1, freq2, freq3, freq4, freq5, freq6, freq7];
        var maxKhz = 0;
        for (var i = 0; i < views.length; i++) {
            var khz = parseInt(views[i].text().trim()) || 0;
            if (khz > maxKhz) maxKhz = khz;
        }
        if (maxKhz > 0)
            root.currentFreq = (maxKhz / 1000000).toFixed(1);
    }

    // /proc/stat for CPU usage
    FileView {
        id: statFile
        path: "/proc/stat"
        blockLoading: true
    }

    function parseStat() {
        var text = statFile.text();
        var line = text.substring(0, text.indexOf("\n")).trim();
        var parts = line.split(/\s+/);
        // parts: [cpu, user, nice, system, idle, iowait, irq, softirq, steal, ...]
        if (parts.length >= 8) {
            var user = parseInt(parts[1]) + parseInt(parts[2]); // user + nice
            var sys = parseInt(parts[3]) + parseInt(parts[6]) + parseInt(parts[7]) + parseInt(parts[8] || 0); // system + irq + softirq + steal
            var total = 0;
            for (var i = 1; i < parts.length; i++)
                total += parseInt(parts[i]) || 0;

            if (root.prevTotal > 0) {
                var diffTotal = total - root.prevTotal;
                if (diffTotal > 0) {
                    root.userPercent = Math.round(100 * (user - root.prevUser) / diffTotal);
                    root.systemPercent = Math.round(100 * (sys - root.prevSystem) / diffTotal);
                    root.usagePercent = root.userPercent + root.systemPercent;
                }
            }
            root.prevUser = user;
            root.prevSystem = sys;
            root.prevTotal = total;
        }

        // Update history
        var h = root.history.slice();
        h.push({user: root.userPercent, sys: root.systemPercent});
        if (h.length > root.maxHistory)
            h.shift();
        root.history = h;
        graphCanvas.requestPaint();
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            statFile.reload();
            root.parseStat();
            freq0.reload(); freq1.reload(); freq2.reload(); freq3.reload();
            freq4.reload(); freq5.reload(); freq6.reload(); freq7.reload();
            root.parseFreq();
        }
    }

    Component.onCompleted: { root.parseStat(); root.parseFreq(); }

    // Fetch power profile
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
