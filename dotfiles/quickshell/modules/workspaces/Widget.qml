import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import "../../core" as Core
import "../../components" as Components
import "../../helpers" as Helpers
import "../../helpers/Format.js" as Format
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: wsRow.implicitWidth + 8
    implicitHeight: parent ? parent.height : 30

    // Claude Code sessions from the shared claude-sessions service (same data the
    // popup uses — no extra daemon stream). Each cell below filters this by its
    // workspace id to show a state-colored project initial per session on it.
    readonly property var ccSessions: {
        var svc = Core.ModuleRegistry.serviceInstance("claude-sessions");
        return svc && svc.sessions ? svc.sessions : [];
    }
    function initial(project) {
        return (project || "?").charAt(0).toUpperCase();
    }
    // Mirrors the claude-sessions state palette (working / needs-input / stopped).
    function stateColor(s) {
        if (s === "working") return "#89b4fa";   // blue
        if (s === "attention") return "#fab387";  // peach
        return "#a6e3a1";                          // green — stopped / ready
    }
    function stateLabel(s) {
        if (s === "working") return "working";
        if (s === "attention") return "needs input";
        return "stopped";
    }
    function since(epoch) {
        if (!epoch) return "";
        var d = Math.max(0, Math.floor(Date.now() / 1000 - epoch));
        if (d < 60) return d + "s";
        if (d < 3600) return Math.floor(d / 60) + "m";
        if (d < 86400) return Math.floor(d / 3600) + "h" + Math.floor((d % 3600) / 60) + "m";
        return Math.floor(d / 86400) + "d" + Math.floor((d % 86400) / 3600) + "h";
    }
    function shortModel(m) {
        if (!m) return "";
        if (m.indexOf("opus") >= 0) return "opus";
        if (m.indexOf("sonnet") >= 0) return "sonnet";
        if (m.indexOf("haiku") >= 0) return "haiku";
        return m;
    }

    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius
        color: Qt.rgba(Helpers.Colors.accent.r, Helpers.Colors.accent.g, Helpers.Colors.accent.b, 0.14)
    }

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
                id: cell
                required property var modelData
                // Sessions whose Hyprland window lives on this workspace (the
                // daemon already orders them by workspace, then start time).
                readonly property var sessions: {
                    var out = [];
                    var all = root.ccSessions;
                    for (var i = 0; i < all.length; i++)
                        if (all[i] && all[i].workspace === cell.modelData.wsId) out.push(all[i]);
                    return out;
                }
                width: Math.max(18, cellRow.implicitWidth + 4)
                height: root.height

                Rectangle {
                    anchors.fill: parent
                    color: cell.modelData.isActive ? Helpers.Colors.wsActiveBg : "transparent"
                    radius: 3

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: Helpers.Colors.wsActive
                        visible: cell.modelData.isActive
                    }
                }

                // Switch to / toggle this workspace. Declared before the label row
                // so the per-session initials (which carry their own click-to-focus)
                // sit on top and win the hit-test; clicks on the bare number fall
                // through to here.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        if (cell.modelData.isSpecial)
                            Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + cell.modelData.name.replace("special:", "") + '")');
                        else
                            Hyprland.dispatch('hl.dsp.focus({workspace=' + cell.modelData.wsId + '})');
                    }
                }

                Row {
                    id: cellRow
                    anchors.centerIn: parent
                    spacing: 1

                    Components.ThemedText {
                        id: wsLabel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: cell.modelData.isSpecial ? 1 : 0
                        text: cell.modelData.label
                        font.pixelSize: cell.modelData.isSpecial ? AppConfig.Config.theme.fontSizeIcon : AppConfig.Config.theme.fontSizeDefault
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        color: {
                            if (cell.modelData.isUrgent) return Helpers.Colors.wsUrgent;
                            if (cell.modelData.isActive) return Helpers.Colors.wsActive;
                            if (!cell.modelData.hasClients && !cell.modelData.isSpecial) return Helpers.Colors.wsEmpty;
                            return Helpers.Colors.wsInactive;
                        }
                    }

                    // Small gap between the workspace number and its session
                    // initials (skipped entirely on workspaces with no sessions).
                    Item {
                        visible: cell.sessions.length > 0
                        width: 3
                        height: 1
                    }

                    // One small project initial per Claude session on this ws,
                    // colored by state and riding high like a superscript; the
                    // focused session's initial is underlined. Hover for the full
                    // stats panel; click to focus that session's window directly.
                    Repeater {
                        model: cell.sessions
                        delegate: Components.ThemedText {
                            id: ini
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -3
                            text: root.initial(modelData.project)
                            color: root.stateColor(modelData.state)
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            font.bold: true
                            font.underline: modelData.focused === true

                            MouseArea {
                                id: iniMouse
                                anchors.fill: parent
                                anchors.margins: -1   // a touch larger so the tiny glyph is easy to hit/hover
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (ini.modelData.address)
                                        Hyprland.dispatch('hl.dsp.focus({ window = "address:' + ini.modelData.address + '" })');
                                }
                            }

                            // Instant stats panel dropped below the bar — same content
                            // as the old standalone chip's tooltip. Parented to the
                            // cell (bar-height) so it lands under the bar, not mid-glyph.
                            ToolTip {
                                id: tip
                                parent: cell
                                visible: iniMouse.containsMouse
                                delay: 0
                                popupType: Popup.Window
                                y: cell.height + 4
                                readonly property var s: ini.modelData
                                readonly property color col: root.stateColor(s.state)
                                readonly property int sz: AppConfig.Config.theme.fontSizeSmall

                                contentItem: Column {
                                    spacing: 2
                                    Components.ThemedText {
                                        text: tip.s.project + (tip.s.focused ? "   ◀ selected" : "")
                                        color: tip.col
                                        font.pixelSize: tip.sz
                                        font.bold: true
                                    }
                                    Components.ThemedText {
                                        text: root.stateLabel(tip.s.state)
                                            + (tip.s.workspace !== null && tip.s.workspace >= 0 ? "   ·   ws " + tip.s.workspace : "")
                                            + (tip.s.startedAt ? "   ·   up " + root.since(tip.s.startedAt) : "")
                                        color: tip.col
                                        font.pixelSize: tip.sz
                                    }
                                    Components.ThemedText {
                                        readonly property string parts: {
                                            var a = [];
                                            if (tip.s.tokens) a.push(Format.tokens(tip.s.tokens) + " tok");
                                            if (tip.s.model) a.push(root.shortModel(tip.s.model));
                                            if (tip.s.branch) a.push(" " + tip.s.branch); // nf branch glyph
                                            return a.join("   ·   ");
                                        }
                                        visible: parts.length > 0
                                        text: parts
                                        muted: true
                                        font.pixelSize: tip.sz
                                    }
                                    Components.ThemedText {
                                        readonly property string body: tip.s.task && tip.s.task.length > 0
                                            ? tip.s.task
                                            : (tip.s.state === "attention" && tip.s.message ? tip.s.message : "")
                                        visible: body.length > 0
                                        width: Math.min(implicitWidth, 360)
                                        elide: Text.ElideRight
                                        text: body
                                        font.pixelSize: tip.sz
                                    }
                                    Components.ThemedText {
                                        width: Math.min(implicitWidth, 360)
                                        elide: Text.ElideMiddle
                                        text: tip.s.cwd
                                        muted: true
                                        font.pixelSize: tip.sz
                                    }
                                    Components.ThemedText {
                                        visible: !!tip.s.zellij
                                        width: Math.min(implicitWidth, 360)
                                        elide: Text.ElideRight
                                        text: tip.s.zellij
                                        muted: true
                                        font.pixelSize: tip.sz
                                    }
                                }
                                background: Rectangle {
                                    color: Qt.rgba(0.12, 0.12, 0.16, 0.97)
                                    border.width: 1
                                    border.color: Qt.rgba(tip.col.r, tip.col.g, tip.col.b, 0.6)
                                    radius: 5
                                }
                            }
                        }
                    }
                }
            }
        }


    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real _scrollAccum: 0
        onWheel: function(wheel) {
            _scrollAccum += wheel.angleDelta.y;
            if (Math.abs(_scrollAccum) < 120) return;
            if (_scrollAccum > 0)
                Hyprland.dispatch('hl.dsp.focus({workspace="e+1"})');
            else
                Hyprland.dispatch('hl.dsp.focus({workspace="e-1"})');

            _scrollAccum = 0;
        }
    }
}
