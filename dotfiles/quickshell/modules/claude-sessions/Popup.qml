import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
// Lists every running Claude Code session with its state and task; clicking a row
// focuses that session's Hyprland window via the daemon.
Item {
    id: root

    property var context: null
    property var screen: null
    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false

    readonly property string sock: AppConfig.Config.daemon.socket

    // Pushed live by the daemon stream via the shared Service (no polling).
    readonly property var sessions: context && context.service ? context.service.sessions : []
    readonly property int total: context && context.service && context.service.counts ? (context.service.counts.total || 0) : 0
    property int nowTick: 0   // bumped every 1s while open so ages keep counting

    readonly property color workingColor: "#89b4fa"
    readonly property color idleColor: "#a6e3a1"
    readonly property color attentionColor: "#fab387"

    implicitWidth: 460
    implicitHeight: screen
        ? Math.min(mainCol.implicitHeight + 32, screen.height - barHeight - AppConfig.Config.theme.popupTopGap - 20)
        : mainCol.implicitHeight + 32

    // Cap the list off the SCREEN (not root.implicitHeight, which derives from the
    // list — that would be a binding loop). Leaves room for header + hint.
    readonly property real maxListHeight: screen
        ? Math.max(120, screen.height - barHeight - AppConfig.Config.theme.popupTopGap - 120)
        : 400

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

    function ago(ts) {
        if (!ts) return "";
        var d = Math.max(0, Math.floor(Date.now() / 1000 - ts));
        if (d < 60) return d + "s";
        if (d < 3600) return Math.floor(d / 60) + "m";
        if (d < 86400) return Math.floor(d / 3600) + "h";
        return Math.floor(d / 86400) + "d";
    }

    Process { id: focusProc; running: false }

    function focusSession(session) {
        if (!session) return;
        focusProc.command = ["curl", "-s", "--unix-socket", root.sock,
            "http://d/claude-sessions/focus?session=" + encodeURIComponent(session.id)];
        focusProc.running = true;
        root.popupOpen = false;
    }

    Timer {
        interval: 1000
        running: root.popupOpen
        repeat: true
        onTriggered: root.nowTick++
    }

    Components.PopupSurface { anchors.fill: parent }

    Column {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Header
        Item {
            width: parent.width
            height: 22
            Components.ThemedText {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Claude sessions"
                color: Helpers.Colors.accent
                font.pixelSize: AppConfig.Config.theme.fontSizeMedium
                font.bold: true
            }
            Components.ThemedText {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.total + (root.total === 1 ? " session" : " sessions")
                muted: true
                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
            }
        }

        // Empty state
        Components.ThemedText {
            visible: root.sessions.length === 0
            width: parent.width
            text: "No Claude Code sessions running."
            muted: true
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
        }

        // Session list
        ListView {
            id: list
            width: parent.width
            height: Math.min(contentHeight, root.maxListHeight)
            visible: root.sessions.length > 0
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: root.sessions

            delegate: Rectangle {
                id: row0
                readonly property bool sel: modelData.focused === true  // currently-focused window
                width: list.width
                height: 50
                radius: 6
                color: sel ? Qt.rgba(1, 1, 1, 0.10)
                           : rowHover.hovered ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02)

                // Accent strip marks the currently-selected session.
                Rectangle {
                    visible: row0.sel
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 2
                    width: 3
                    radius: 2
                    color: root.stateColor(modelData.state)
                }

                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.focusSession(modelData) }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // State dot
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9
                        height: 9
                        radius: 4.5
                        color: root.stateColor(modelData.state)
                    }

                    // Project + task
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 9 - 10 - rightCol.width - 20
                        spacing: 1

                        Components.ThemedText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.project + (modelData.workspace >= 0 && modelData.workspace !== null ? "  ·  ws " + modelData.workspace : "")
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            font.bold: true
                        }
                        Components.ThemedText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: modelData.task && modelData.task.length > 0
                                ? modelData.task
                                : (modelData.state === "attention" && modelData.message ? modelData.message : modelData.cwd)
                            muted: true
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        }
                    }

                    // State label + age
                    Column {
                        id: rightCol
                        anchors.verticalCenter: parent.verticalCenter
                        width: 78

                        Components.ThemedText {
                            anchors.right: parent.right
                            text: root.stateLabel(modelData.state)
                            color: root.stateColor(modelData.state)
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            font.bold: true
                        }
                        Components.ThemedText {
                            anchors.right: parent.right
                            text: { root.nowTick; return root.ago(modelData.ts) + (modelData.hooked ? "" : " ~"); }
                            muted: true
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        }
                    }
                }
            }
        }

        // Hint
        Components.ThemedText {
            visible: root.sessions.length > 0
            width: parent.width
            text: "Click a session to focus its window"
            muted: true
            font.pixelSize: AppConfig.Config.theme.fontSizeSmall * 0.9
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
