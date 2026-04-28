import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../../helpers" as Helpers

Item {
    id: root
    implicitWidth: expanded ? Math.max(212, (appIcon.visible ? 22 : 0) + titleText.implicitWidth + 12) : 212
    implicitHeight: parent ? parent.height : 30

    property var screen: null

    property bool expanded: false

    property var activeTl: Hyprland.activeToplevel

    property string appId: {
        if (!activeTl) return "";
        if (activeTl.wayland && activeTl.wayland.appId) return activeTl.wayland.appId;
        if (activeTl.lastIpcObject && activeTl.lastIpcObject.class) return activeTl.lastIpcObject.class;
        return "";
    }

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
        if (root.expanded) return root.fullTitle;
        if (root.fullTitle.length > 32)
            return root.fullTitle.substring(0, 32);
        return root.fullTitle;
    }

    property string iconSource: {
        if (root.fullTitle === "") return "";
        if (!root.appId) return "";
        var entry = DesktopEntries.heuristicLookup(root.appId);
        if (entry && entry.icon) return Quickshell.iconPath(entry.icon, true) ?? "";
        return Quickshell.iconPath(root.appId.toLowerCase(), true) ?? "";
    }

    Item {
        anchors.fill: parent

        Image {
            id: appIcon
            width: 16
            height: 16
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            sourceSize.width: 16
            sourceSize.height: 16
            source: root.iconSource
            visible: source !== "" && status === Image.Ready
        }

        Item {
            anchors.left: appIcon.visible ? appIcon.right : parent.left
            anchors.leftMargin: appIcon.visible ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: 200 - (appIcon.visible ? 22 : 0)
            height: parent.height

            Text {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                width: root.expanded ? implicitWidth : parent.width
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
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                root.expanded = !root.expanded;
            } else if (mouse.button === Qt.RightButton) {
                copyProc.command = ["bash", "-c", "VAR=$(hyprctl activewindow -j | jq -r .title) && wl-copy \"$VAR\" && notify-send -u low -t 2000 'Window title' \"$VAR\""];
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
