import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: Math.max(16, langText.implicitWidth + 4)
    implicitHeight: parent ? parent.height : 30

    property string layout: ""

    property color langColor: {
        switch (layout) {
            case "en": return "#42a5f5";
            case "uk": return "#ffb74d";
            case "ru": return "#ef5350";
            case "de": return "#a6e3a1";
            case "es": return "#f38ba8";
            default: return Helpers.Colors.textDefault;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                var parts = event.data.split(",");
                if (parts.length >= 2) {
                    root.layout = parts[parts.length - 1].trim().substring(0, 2).toLowerCase();
                }
            }
        }
    }

    Socket {
        id: initSocket
        path: Hyprland.requestSocketPath
        parser: SplitParser {
            splitMarker: ""
            onRead: data => {
                try {
                    var devices = JSON.parse(data);
                    var keyboards = devices.keyboards;
                    if (keyboards && keyboards.length > 0) {
                        root.layout = keyboards[0].active_keymap.substring(0, 2).toLowerCase();
                    }
                } catch(e) {}
                initSocket.connected = false;
            }
        }
    }

    Component.onCompleted: {
        initSocket.connected = true;
        initSocket.write("j/devices");
        initSocket.flush();
    }

    Text {
        id: langText
        anchors.centerIn: parent
        text: root.layout.charAt(0).toUpperCase()
        color: root.langColor
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeDefault
        font.bold: true
    }
}
