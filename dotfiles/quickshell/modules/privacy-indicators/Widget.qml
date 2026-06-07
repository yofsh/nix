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
                text: entry.apps
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

    // Format detected processes for the tooltip: "name [pid] full params".
    function fmtApps(entries) {
        if (!entries || !entries.length) return "";
        var out = [];
        for (var i = 0; i < entries.length; i++) {
            var e = entries[i];
            var s = e.name || "?";
            if (e.pid) s += " [" + e.pid + "]";
            if (e.params) s += "  " + e.params;
            out.push(s);
        }
        return out.join("    ·    ");
    }

    function applyLine(text) {
        if (!text) return;
        try {
            var d = JSON.parse(text.trim());
            root.micActive = !!(d.mic && d.mic.length > 0);
            root.camActive = !!(d.cam && d.cam.length > 0);
            root.screenActive = !!(d.screen && d.screen.length > 0);
            root.micApps = fmtApps(d.mic);
            root.camApps = fmtApps(d.cam);
            root.screenApps = fmtApps(d.screen);
        } catch (e) { /* ignore parse errors */ }
    }

    // Event-driven: the daemon pushes {mic,cam,screen} on connect + on every
    // change (mic via pactl-subscribe, screen/cam via pw-mon). No polling.
    Process {
        id: streamProc
        command: ["curl", "-sN", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/privacy/stream"]
        running: true
        onRunningChanged: if (!running) running = true   // auto-reconnect
        stdout: SplitParser { onRead: line => root.applyLine(line) }
    }
}
