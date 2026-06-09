import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

// One chip per running Claude Code session, in stable start-order (new sessions
// append at the end, existing ones never reshuffle). Each chip shows the
// project's initial, colored by status (working/stopped/needs-input). Hover
// expands it to the project + session name; click focuses that window. Pure
// consumer of the daemon stream via the shared Service — no polling.
Item {
    id: root
    property var context: null

    readonly property var sessions: context && context.service ? context.service.sessions : []
    readonly property string sock: AppConfig.Config.daemon.socket
    property int hoveredIndex: -1

    readonly property color workingColor: "#89b4fa"   // blue — working
    readonly property color idleColor: "#a6e3a1"      // green — stopped / ready
    readonly property color attentionColor: "#fab387" // peach — needs input

    function stateColor(s) {
        if (s === "working") return workingColor;
        if (s === "attention") return attentionColor;
        return idleColor;
    }
    function stateLabel(s) {
        if (s === "working") return "working";
        if (s === "attention") return "needs input";
        return "stopped";
    }
    function initial(project) {
        return (project || "?").charAt(0).toUpperCase();
    }
    function since(epoch) {
        if (!epoch) return "";
        var d = Math.max(0, Math.floor(Date.now() / 1000 - epoch));
        if (d < 60) return d + "s";
        if (d < 3600) return Math.floor(d / 60) + "m";
        if (d < 86400) return Math.floor(d / 3600) + "h" + Math.floor((d % 3600) / 60) + "m";
        return Math.floor(d / 86400) + "d" + Math.floor((d % 86400) / 3600) + "h";
    }
    function fmtTokens(t) {
        if (!t) return "";
        if (t >= 1e6) return (t / 1e6).toFixed(1) + "M";
        if (t >= 1e3) return Math.round(t / 1e3) + "k";
        return "" + t;
    }
    function shortModel(m) {
        if (!m) return "";
        if (m.indexOf("opus") >= 0) return "opus";
        if (m.indexOf("sonnet") >= 0) return "sonnet";
        if (m.indexOf("haiku") >= 0) return "haiku";
        return m;
    }

    visible: sessions.length > 0
    implicitWidth: visible ? row.implicitWidth + 8 : 0
    implicitHeight: parent ? parent.height : 30

    Process { id: focusProc; running: false }
    function focusSession(id) {
        focusProc.command = ["curl", "-s", "--unix-socket", root.sock,
            "http://d/claude-sessions/focus?session=" + encodeURIComponent(id)];
        focusProc.running = true;
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: root.sessions

            delegate: Rectangle {
                id: chip
                readonly property bool hov: root.hoveredIndex === index
                readonly property bool sel: modelData.focused === true  // its window is focused now
                readonly property color col: root.stateColor(modelData.state)

                height: root.height - 6
                width: chipRow.implicitWidth + 10
                radius: 4
                // Selected session = solid fill (stands out); others = subtle outline.
                color: sel ? Qt.rgba(col.r, col.g, col.b, 0.9)
                           : Qt.rgba(col.r, col.g, col.b, hov ? 0.30 : 0.16)
                border.width: sel ? 1.5 : 1
                border.color: sel ? col : Qt.rgba(col.r, col.g, col.b, 0.55)
                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 140 } }

                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.initial(modelData.project)
                        // Dark glyph on the solid selected fill; status-colored otherwise.
                        color: chip.sel ? "#11111b" : chip.col
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        font.bold: true
                    }

                    // --- Inline hover-expand effect (disabled; kept for reference) ---
                    // Expanding hover label: project + session (zellij) name,
                    // capped so a long session name doesn't shove the whole bar.
                    // Replaced by the instant ToolTip below. To restore, drop the
                    // ToolTip and un-comment this.
                    // Item {
                    //     anchors.verticalCenter: parent.verticalCenter
                    //     height: lbl.implicitHeight
                    //     width: chip.hov ? Math.min(lbl.implicitWidth, 240) : 0
                    //     clip: true
                    //     opacity: chip.hov ? 1 : 0
                    //     Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    //     Behavior on opacity { NumberAnimation { duration: 160 } }
                    //
                    //     Text {
                    //         id: lbl
                    //         anchors.verticalCenter: parent.verticalCenter
                    //         width: 240
                    //         elide: Text.ElideRight
                    //         text: modelData.project + "  ·  " + (modelData.zellij || modelData.id)
                    //         color: Helpers.Colors.textDefault
                    //         font.family: AppConfig.Config.theme.fontFamily
                    //         font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    //     }
                    // }
                }

                // Instant hover tooltip: a small stats panel dropped below the
                // chip. delay:0 = appears the moment you hover. popupType:Window so
                // it renders as a real surface instead of being clipped by the bar.
                ToolTip {
                    id: tip
                    parent: chip
                    visible: chip.hov
                    delay: 0
                    popupType: Popup.Window
                    y: chip.height + 4
                    readonly property var s: modelData
                    readonly property string fam: AppConfig.Config.theme.fontFamily
                    readonly property int sz: AppConfig.Config.theme.fontSizeSmall

                    contentItem: Column {
                        spacing: 2

                        // project — bold, status-colored, with a focused marker
                        Text {
                            text: tip.s.project + (tip.s.focused ? "   ◀ selected" : "")
                            color: chip.col
                            font.family: tip.fam
                            font.pixelSize: tip.sz
                            font.bold: true
                        }
                        // state · workspace · uptime
                        Text {
                            text: root.stateLabel(tip.s.state)
                                + (tip.s.workspace !== null && tip.s.workspace >= 0 ? "   ·   ws " + tip.s.workspace : "")
                                + (tip.s.startedAt ? "   ·   up " + root.since(tip.s.startedAt) : "")
                            color: chip.col
                            font.family: tip.fam
                            font.pixelSize: tip.sz
                        }
                        // tokens · model · git branch
                        Text {
                            readonly property string parts: {
                                var a = [];
                                if (tip.s.tokens) a.push(root.fmtTokens(tip.s.tokens) + " tok");
                                if (tip.s.model) a.push(root.shortModel(tip.s.model));
                                if (tip.s.branch) a.push(" " + tip.s.branch); // nf branch glyph
                                return a.join("   ·   ");
                            }
                            visible: parts.length > 0
                            text: parts
                            color: Helpers.Colors.textMuted
                            font.family: tip.fam
                            font.pixelSize: tip.sz
                        }
                        // current task / pending message
                        Text {
                            readonly property string body: tip.s.task && tip.s.task.length > 0
                                ? tip.s.task
                                : (tip.s.state === "attention" && tip.s.message ? tip.s.message : "")
                            visible: body.length > 0
                            width: Math.min(implicitWidth, 360)
                            elide: Text.ElideRight
                            text: body
                            color: Helpers.Colors.textDefault
                            font.family: tip.fam
                            font.pixelSize: tip.sz
                        }
                        // working directory
                        Text {
                            width: Math.min(implicitWidth, 360)
                            elide: Text.ElideMiddle
                            text: tip.s.cwd
                            color: Helpers.Colors.textMuted
                            font.family: tip.fam
                            font.pixelSize: tip.sz
                        }
                        // zellij session name
                        Text {
                            visible: !!tip.s.zellij
                            width: Math.min(implicitWidth, 360)
                            elide: Text.ElideRight
                            text: tip.s.zellij
                            color: Helpers.Colors.textMuted
                            font.family: tip.fam
                            font.pixelSize: tip.sz
                        }
                    }
                    background: Rectangle {
                        color: Qt.rgba(0.12, 0.12, 0.16, 0.97)
                        border.width: 1
                        border.color: Qt.rgba(chip.col.r, chip.col.g, chip.col.b, 0.6)
                        radius: 5
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onEntered: root.hoveredIndex = index
                    onExited: if (root.hoveredIndex === index) root.hoveredIndex = -1
                    onClicked: root.focusSession(modelData.id)
                }
            }
        }
    }
}
