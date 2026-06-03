import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: visible ? row.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 30
    visible: anyActive
    Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.InOutQuad } }

    property var context: null
    property var config: Helpers.ModuleConfig.resolve("privacy-indicators")
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
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/privacy/check"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                var text = this.text.trim();
                root.micActive = false; root.camActive = false; root.screenActive = false;
                root.micApps = ""; root.camApps = ""; root.screenApps = "";
                if (text) {
                    try {
                        var d = JSON.parse(text);
                        if (d.mic && d.mic.length > 0) { root.micActive = true; root.micApps = d.mic.join(","); }
                        if (d.cam && d.cam.length > 0) { root.camActive = true; root.camApps = d.cam.join(","); }
                        if (d.screen && d.screen.length > 0) { root.screenActive = true; root.screenApps = d.screen.join(","); }
                    } catch (e) {}
                }
            }
        }
    }

    Timer {
        interval: root.config.intervalMs
        running: true
        repeat: true
        onTriggered: checkProc.running = true
    }
}
