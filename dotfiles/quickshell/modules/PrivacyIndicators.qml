import QtQuick
import Quickshell.Io
import "../helpers" as Helpers
import "../config" as AppConfig

Item {
    id: root
    implicitWidth: row.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30
    visible: opacity > 0
    opacity: anyActive ? 1.0 : 0.0
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

    property bool micActive: false
    property bool camActive: false
    property bool screenActive: false
    property string micApps: ""
    property string camApps: ""
    property string screenApps: ""
    property bool anyActive: micActive || camActive || screenActive
    property bool hovered: false

    // Reusable inline component: icon + expanding app label
    component PrivacyEntry: Row {
        id: entry
        property bool active: false
        property string icon: ""
        property string apps: ""
        property bool showLabel: root.hovered

        visible: active
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: entry.icon
            color: Helpers.Colors.mutedRed
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            height: labelText.implicitHeight
            width: entry.showLabel ? labelText.implicitWidth : 0
            clip: true
            opacity: entry.showLabel ? 1.0 : 0.0
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Text {
                id: labelText
                anchors.verticalCenter: parent.verticalCenter
                text: entry.apps.replace(/,/g, ", ")
                color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
            }
        }
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        PrivacyEntry { active: root.micActive; icon: "\uF130"; apps: root.micApps }
        PrivacyEntry { active: root.camActive; icon: "\uF03D"; apps: root.camApps }
        PrivacyEntry { active: root.screenActive; icon: "\uF108"; apps: root.screenApps }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered = true
        onExited: root.hovered = false
    }

    Process {
        id: checkProc
        command: ["privacy-check"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                var mic = false, cam = false, screen = false;
                var micA = "", camA = "", screenA = "";
                if (text) {
                    var lines = text.split("\n");
                    for (var i = 0; i < lines.length; i++) {
                        var line = lines[i];
                        if (line.indexOf("MIC:") === 0) {
                            mic = true;
                            micA = line.substring(4);
                        } else if (line.indexOf("CAM:") === 0) {
                            cam = true;
                            camA = line.substring(4);
                        } else if (line.indexOf("SCREEN:") === 0) {
                            screen = true;
                            screenA = line.substring(7);
                        }
                    }
                }
                root.micActive = mic;
                root.camActive = cam;
                root.screenActive = screen;
                root.micApps = micA;
                root.camApps = camA;
                root.screenApps = screenA;
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: checkProc.running = true
    }
}
