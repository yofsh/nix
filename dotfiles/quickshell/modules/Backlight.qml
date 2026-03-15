import QtQuick
import Quickshell.Io
import "../helpers" as Helpers
import "../config" as AppConfig

Item {
    id: root
    visible: maxBrightnessFile.text().trim() !== ""
    implicitWidth: visible ? blText.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 30

    property string backlightPath: AppConfig.Config.backlight.devicePath

    property string displayText: {
        var cur = parseInt(brightnessFile.text().trim()) || 0;
        var max = parseInt(maxBrightnessFile.text().trim()) || 1;
        return max > 0 ? Math.round(cur / max * 100) + "" : "";
    }

    FileView {
        id: brightnessFile
        path: root.backlightPath + "/brightness"
        blockLoading: true
        watchChanges: root.visible
        onFileChanged: this.reload()
    }

    FileView {
        id: maxBrightnessFile
        path: root.backlightPath + "/max_brightness"
        blockLoading: true
    }

    Text {
        id: blText
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: Helpers.Colors.backlight
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeDefault
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real _scrollAccum: 0
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                setProc.command = ["brightnessctl", "set", AppConfig.Config.backlight.leftClickValue];
                setProc.running = true;
            } else {
                setProc.command = ["brightnessctl", "set", AppConfig.Config.backlight.rightClickValue];
                setProc.running = true;
            }
        }
        onWheel: function(wheel) {
            _scrollAccum += wheel.angleDelta.y;
            if (Math.abs(_scrollAccum) < 120) return;
            if (_scrollAccum > 0) {
                setProc.command = ["brightnessctl", "set", AppConfig.Config.backlight.scrollStepUp];
            } else {
                setProc.command = ["brightnessctl", "set", AppConfig.Config.backlight.scrollStepDown];
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
