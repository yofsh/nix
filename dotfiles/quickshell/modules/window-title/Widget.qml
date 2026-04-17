import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../helpers" as Helpers

Item {
    id: root
    implicitWidth: hovered ? Math.max(212, titleText.implicitWidth + 12) : 212
    implicitHeight: parent ? parent.height : 30

    property var screen: null

    property bool hovered: false

    property string fullTitle: {
        var toplevel = Hyprland.activeToplevel;
        if (!toplevel) return "";

        // separate-outputs: only show if this toplevel is on our monitor
        if (root.screen) {
            var mon = Hyprland.monitorFor(root.screen);
            if (mon && mon.activeWorkspace) {
                var fMon = Hyprland.focusedMonitor;
                if (fMon && fMon.id !== mon.id) return "";
            }
        }

        var title = toplevel.title || "";

        // Firefox title rewrite
        if (title.indexOf(" — Mozilla Firefox") !== -1) {
            title = title.replace(" — Mozilla Firefox", "") + " - 🌎";
        }

        return title;
    }

    property string displayTitle: {
        if (root.hovered) return root.fullTitle;
        if (root.fullTitle.length > 32)
            return root.fullTitle.substring(0, 32);
        return root.fullTitle;
    }

    Item {
        width: parent.width
        height: parent.height

        Item {
            anchors.left: parent.left
            anchors.leftMargin: 0
            anchors.verticalCenter: parent.verticalCenter
            width: 200
            height: parent.height

            Text {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                width: root.hovered ? implicitWidth : 200
                text: root.displayTitle
                color: Helpers.Colors.windowTitle
                font.family: "DejaVu Sans"
                font.pixelSize: 12
                elide: Text.ElideNone
                clip: true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                copyProc.command = ["bash", "-c", "VAR=$(hyprctl activewindow -j | jq -r .title) && wl-copy \"$VAR\" && notify-send -u low -t 2000 'Window title' \"$VAR\""];
                copyProc.running = true;
            } else if (mouse.button === Qt.RightButton) {
                copyProc.command = ["bash", "-c", "VAR=$(hyprctl activewindow -j | jq -r .class) && wl-copy \"$VAR\" && notify-send -u low -t 2000 'Window class' \"$VAR\""];
                copyProc.running = true;
            } else if (mouse.button === Qt.MiddleButton) {
                copyProc.command = ["bash", "-c", "VAR=$(hyprctl activewindow) && wl-copy \"$VAR\" && notify-send -u low -t 2000 'Window hyprland info' \"$VAR\""];
                copyProc.running = true;
            }
        }
    }

    Process {
        id: copyProc
        command: []
        running: false
    }
}
