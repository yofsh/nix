import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: Math.max(16, langText.implicitWidth + 4)
    implicitHeight: parent ? parent.height : 30

    property string layout: ""

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") {
                // event data format: "keyboard_name,layout_name"
                var parts = event.data.split(",");
                if (parts.length >= 2) {
                    root.layout = parts[parts.length - 1].trim().substring(0, 2).toLowerCase();
                }
            }
        }
    }

    // Fetch initial layout via Hyprland request socket
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
        text: root.layout
        color: Helpers.Colors.textDefault
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 12
    }
}
