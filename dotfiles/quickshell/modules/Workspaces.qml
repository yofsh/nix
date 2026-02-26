import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: wsRow.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30

    property var specialIcons: ({
        "special:ha": "󰟐",
        "special:term": "󰆍",
        "special:music": "󰎇",
        "special:tg": "󰒊",
        "special:audio": "󰖀",
        "special:bt": "󰂯",
        "special:gpt": "󰚩",
        "special:obsidian": "󱓧"
    })

    property var persistentIds: [1, 2, 3, 4, 5, 6, 7, 8]

    // Track visible special workspaces via activespecial event
    // Map of monitorName -> specialWorkspaceName (e.g. {"DP-1": "special:term"})
    property var activeSpecials: ({})

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activespecial") {
                var sep = event.data.lastIndexOf(",");
                var wsName = sep >= 0 ? event.data.substring(0, sep).trim() : "";
                var monName = sep >= 0 ? event.data.substring(sep + 1).trim() : "";
                var updated = Object.assign({}, root.activeSpecials);
                if (wsName) {
                    updated[monName] = wsName;
                } else {
                    delete updated[monName];
                }
                root.activeSpecials = updated;
            }
        }
    }

    // Build merged workspace list: persistent 1-8 + any active specials
    property var workspaceModel: {
        // Touch reactive dependencies
        var allWs = Hyprland.workspaces ? Hyprland.workspaces.values : [];
        var fw = Hyprland.focusedWorkspace;
        var specials = root.activeSpecials;

        var result = [];
        if (!allWs) return result;

        var wsById = {};

        for (var i = 0; i < allWs.length; i++) {
            var ws = allWs[i];
            if (ws) wsById[ws.id] = ws;
        }

        // Always show persistent workspaces 1-8
        for (var j = 0; j < persistentIds.length; j++) {
            var pid = persistentIds[j];
            var existing = wsById[pid] || null;
            result.push({
                wsId: pid,
                name: "" + pid,
                label: "" + pid,
                isSpecial: false,
                hasClients: existing && existing.toplevels && existing.toplevels.values ? existing.toplevels.values.length > 0 : false,
                isActive: fw ? fw.id === pid : false,
                isUrgent: existing ? existing.urgent : false
            });
        }

        // Check if a special workspace is currently visible on any monitor
        var activeSpecialNames = {};
        for (var mon in specials) {
            activeSpecialNames[specials[mon]] = true;
        }

        // Add active special workspaces (negative IDs)
        for (var k = 0; k < allWs.length; k++) {
            var sws = allWs[k];
            if (sws && sws.id < 0) {
                var icon = specialIcons[sws.name] || sws.name.replace("special:", "");
                result.push({
                    wsId: sws.id,
                    name: sws.name,
                    label: icon,
                    isSpecial: true,
                    hasClients: true,
                    isActive: !!activeSpecialNames[sws.name],
                    isUrgent: sws.urgent
                });
            }
        }

        return result;
    }

    Row {
        id: wsRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Item { width: 2; height: 1 }

        Repeater {
            model: root.workspaceModel

            Item {
                required property var modelData
                width: Math.max(24, wsLabel.implicitWidth + 4)
                height: root.height

                Rectangle {
                    anchors.fill: parent
                    color: modelData.isActive ? Helpers.Colors.wsActiveBg : "transparent"
                    radius: 3

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Helpers.Colors.wsActive
                        visible: modelData.isActive
                    }
                }

                Text {
                    id: wsLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    color: {
                        if (modelData.isUrgent) return Helpers.Colors.wsUrgent;
                        if (modelData.isActive) return Helpers.Colors.wsActive;
                        if (!modelData.hasClients && !modelData.isSpecial) return Helpers.Colors.wsEmpty;
                        return Helpers.Colors.wsInactive;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        if (modelData.isSpecial) {
                            Hyprland.dispatch("togglespecialworkspace " + modelData.name.replace("special:", ""));
                        } else {
                            Hyprland.dispatch("workspace " + modelData.wsId);
                        }
                    }
                }
            }
        }

        Item { width: 25; height: 1 }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real _scrollAccum: 0
        onWheel: function(wheel) {
            _scrollAccum += wheel.angleDelta.y;
            if (Math.abs(_scrollAccum) < 120) return;
            if (_scrollAccum > 0)
                Hyprland.dispatch("workspace e+1");
            else
                Hyprland.dispatch("workspace e-1");
            _scrollAccum = 0;
        }
    }
}
