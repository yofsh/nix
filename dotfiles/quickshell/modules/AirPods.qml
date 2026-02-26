import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: visible ? contentRow.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 30
    visible: connected

    property bool connected: false
    property int battLeft: 0
    property int battRight: 0
    property int battCase: 0
    property string noiseMode: "off"
    property bool leftInEar: false
    property bool rightInEar: false
    property bool hovered: false

    function parseOutput(text) {
        var parts = text.trim().split("|");
        if (parts.length < 7) {
            root.connected = false;
            return;
        }
        root.connected = parts[0] === "true";
        root.battLeft = parseInt(parts[1]) || 0;
        root.battRight = parseInt(parts[2]) || 0;
        root.battCase = parseInt(parts[3]) || 0;
        root.noiseMode = parts[4].replace(/"/g, "");
        root.leftInEar = parts[5] === "true";
        root.rightInEar = parts[6] === "true";
    }

    function battColor(level) {
        if (level <= 15) return Helpers.Colors.batteryCritical;
        if (level <= 30) return Helpers.Colors.batteryWarning;
        return Helpers.Colors.headsetBattery;
    }

    function noiseModeIcon(mode) {
        if (mode === "noise-cancellation") return "󰩅";  // nf-md-ear_hearing_off
        if (mode === "transparency") return "󰟅";         // nf-md-ear_hearing
        if (mode === "adaptive") return "󱫮";              // nf-md-ear_hearing_loop
        return "󱡐";                                       // nf-md-earbuds_off
    }

    function noiseModeColor(mode) {
        if (mode === "noise-cancellation") return "#a6e3a1";
        if (mode === "transparency") return "#f9e2af";
        if (mode === "adaptive") return "#89b4fa";
        return Helpers.Colors.textMuted;
    }

    function setNoiseMode(mode) {
        setModeProc.command = ["busctl", "--user", "call",
            "me.kavishdevar.LibrePods", "/me/kavishdevar/LibrePods",
            "me.kavishdevar.LibrePods", "SetNoiseControlMode",
            "s", mode];
        setModeProc.running = true;
    }

    property var modes: [
        { value: "noise-cancellation", icon: "󰩅", short: "NC" },
        { value: "transparency",       icon: "󰟅", short: "TR" },
        { value: "adaptive",           icon: "󱫮", short: "AD" },
        { value: "off",                icon: "󱡐", short: "OFF" }
    ]

    // Find which picker mode index the mouse is over (-1 if none)
    function modeIndexAt(mouseX, mouseY) {
        var pos = mouseArea.mapToItem(pickerRow, mouseX, mouseY);
        for (var i = 0; i < root.modes.length; i++) {
            var item = pickerRepeater.itemAt(i);
            if (item && pos.x >= item.x && pos.x < item.x + item.width)
                return i;
        }
        return -1;
    }

    Row {
        id: contentRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        height: parent.height

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: root.battLeft + ""
            visible: root.battLeft > 0
            color: root.battColor(root.battLeft)
            opacity: root.leftInEar ? 1.0 : 0.4
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: root.battRight + ""
            visible: root.battRight > 0
            color: root.battColor(root.battRight)
            opacity: root.rightInEar ? 1.0 : 0.4
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }

        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: root.battCase + ""
            visible: root.battCase > 0
            color: root.battColor(root.battCase)
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 12
        }

        // Active mode icon (always visible)
        Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: root.noiseModeIcon(root.noiseMode)
            color: root.noiseModeColor(root.noiseMode)
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 14
        }

        // Expandable picker with all mode icons
        Item {
            id: pickerWrapper
            height: parent.height
            width: root.hovered ? pickerMeasure.implicitWidth : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            Row {
                id: pickerRow
                height: parent.height
                spacing: 6

                Repeater {
                    id: pickerRepeater
                    model: root.modes

                    Item {
                        id: modeItem
                        required property var modelData
                        required property int index
                        property bool isActive: modelData.value === root.noiseMode
                        width: modeRow.implicitWidth
                        height: pickerRow.height
                        opacity: isActive ? 1.0
                               : (mouseArea.hoveredModeIndex === index ? 0.8 : 0.35)

                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }

                        Row {
                            id: modeRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                text: modeItem.modelData.icon
                                color: root.noiseModeColor(modeItem.modelData.value)
                                font.family: "DejaVuSansM Nerd Font"
                                font.pixelSize: 14
                            }

                            Text {
                                text: modeItem.modelData.short
                                color: root.noiseModeColor(modeItem.modelData.value)
                                font.family: "DejaVuSansM Nerd Font"
                                font.pixelSize: 10
                            }
                        }
                    }
                }
            }
        }
    }

    // Hidden row to measure expanded picker width
    Row {
        id: pickerMeasure
        visible: false
        spacing: 6
        Repeater {
            model: root.modes
            Row {
                required property var modelData
                spacing: 1
                Text {
                    text: modelData.icon
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 14
                }
                Text {
                    text: modelData.short
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 10
                }
            }
        }
    }

    // Single MouseArea on top — handles hover + clicks (like Media/Network)
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true

        property int hoveredModeIndex: root.hovered ? root.modeIndexAt(mouseX, mouseY) : -1

        onEntered: root.hovered = true
        onExited: root.hovered = false

        onClicked: {
            if (hoveredModeIndex >= 0 && hoveredModeIndex < root.modes.length) {
                var mode = root.modes[hoveredModeIndex].value;
                if (mode !== root.noiseMode)
                    root.setNoiseMode(mode);
            }
        }
    }

    // Poll all D-Bus properties in a single call
    Process {
        id: pollProc
        command: ["bash", "-c",
            "busctl --user get-property me.kavishdevar.LibrePods " +
            "/me/kavishdevar/LibrePods me.kavishdevar.LibrePods " +
            "Connected BatteryLeftLevel BatteryRightLevel BatteryCaseLevel " +
            "NoiseControlMode LeftPodInEar RightPodInEar 2>/dev/null " +
            "| cut -d' ' -f2 | paste -sd'|'"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.parseOutput(this.text)
        }
    }

    Timer {
        id: pollTimer
        interval: 5000
        running: true
        repeat: true
        onTriggered: pollProc.running = true
    }

    // Debounce rapid signal bursts into a single refresh
    Timer {
        id: signalDebounce
        interval: 200
        onTriggered: pollProc.running = true
    }

    // Monitor D-Bus signals for immediate updates
    Process {
        id: monitorProc
        running: true
        command: ["dbus-monitor", "--session",
            "type='signal',interface='me.kavishdevar.LibrePods'"]
        stdout: SplitParser {
            onRead: data => signalDebounce.restart()
        }
    }

    // Restart monitor if it dies
    Timer {
        id: monitorRestart
        interval: 10000
        running: !monitorProc.running
        onTriggered: monitorProc.running = true
    }

    // Set noise control mode
    Process {
        id: setModeProc
        command: []
        running: false
    }
}
