import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: blText.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30

    property string displayText: {
        var cur = parseInt(brightnessFile.text().trim()) || 0;
        var max = parseInt(maxBrightnessFile.text().trim()) || 1;
        return max > 0 ? Math.round(cur / max * 100) + "" : "";
    }

    FileView {
        id: brightnessFile
        path: "/sys/class/backlight/intel_backlight/brightness"
        blockLoading: true
        watchChanges: true
        onFileChanged: this.reload()
    }

    FileView {
        id: maxBrightnessFile
        path: "/sys/class/backlight/intel_backlight/max_brightness"
        blockLoading: true
    }

    Text {
        id: blText
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: Helpers.Colors.backlight
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 12
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real _scrollAccum: 0
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                setProc.command = ["light", "-S", "15"];
                setProc.running = true;
            } else {
                setProc.command = ["light", "-S", "1"];
                setProc.running = true;
            }
        }
        onWheel: function(wheel) {
            _scrollAccum += wheel.angleDelta.y;
            if (Math.abs(_scrollAccum) < 120) return;
            if (_scrollAccum > 0) {
                setProc.command = ["light", "-A", "5"];
            } else {
                setProc.command = ["light", "-U", "5"];
            }
            _scrollAccum = 0;
            setProc.running = true;
        }
    }

    Process {
        id: setProc
        command: []
        running: false
        onExited: brightnessFile.reload()
    }
}
