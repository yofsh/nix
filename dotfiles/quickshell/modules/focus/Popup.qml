import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
Item {
    id: root

    property var context: null
    property var screen: null
    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false

    implicitWidth: 360
    implicitHeight: screen
        ? Math.min(mainCol.implicitHeight + 32, screen.height - barHeight - 40)
        : mainCol.implicitHeight + 32

    // Keyboard input for the label field is enabled via PackagePopup { keyboardFocus: true }.

    readonly property string sock: AppConfig.Config.daemon.socket

    // -- active focus state --
    property bool active: false
    property bool paused: false
    property real endAt: 0
    property int remaining: 0
    property int planned: 0
    property string label: ""
    property var sessions: []

    readonly property var presets: [
        { label: "15m", secs: 900 },
        { label: "25m", secs: 1500 },
        { label: "45m", secs: 2700 },
        { label: "60m", secs: 3600 },
        { label: "90m", secs: 5400 }
    ]

    function fmt(s) {
        s = Math.max(0, Math.round(s));
        var h = Math.floor(s / 3600);
        var m = Math.floor((s % 3600) / 60);
        var sec = s % 60;
        function p(n) { return (n < 10 ? "0" : "") + n; }
        if (h > 0) return h + ":" + p(m) + ":" + p(sec);
        return m + ":" + p(sec);
    }

    function clock(iso) {
        if (!iso) return "—";
        var d = new Date(iso);
        function p(n) { return (n < 10 ? "0" : "") + n; }
        return p(d.getHours()) + ":" + p(d.getMinutes());
    }

    function applyState(d) {
        if (!d || !d.active) {
            root.active = false;
            root.paused = false;
            root.remaining = 0;
            root.planned = 0;
            root.label = "";
            return;
        }
        root.active = true;
        root.paused = !!d.paused;
        root.label = d.label || "";
        root.endAt = d.endAt || 0;
        root.remaining = d.remaining || 0;
        root.planned = d.plannedSeconds || 0;
    }

    onPopupOpenChanged: {
        if (popupOpen) {
            stateProc.running = true;
            historyProc.running = true;
            autofocusTimer.restart();
        }
    }

    // Autofocus the goal field once the surface has grabbed keyboard focus.
    Timer {
        id: autofocusTimer
        interval: 60
        repeat: false
        onTriggered: {
            if (root.popupOpen && !root.active)
                labelField.forceActiveFocus();
        }
    }

    // -- daemon I/O ----------------------------------------------------------

    Process {
        id: stateProc
        command: ["curl", "-s", "--unix-socket", root.sock, "http://d/focus/state"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: { try { root.applyState(JSON.parse(this.text)); } catch (e) {} }
        }
    }

    Process {
        id: historyProc
        command: ["curl", "-s", "--unix-socket", root.sock, "http://d/focus/history?limit=12"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    root.sessions = d.sessions || [];
                } catch (e) {}
            }
        }
    }

    Process {
        id: actionProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.applyState(JSON.parse(this.text)); } catch (e) {}
                historyProc.running = true;
            }
        }
    }

    function action(path) {
        actionProc.command = ["curl", "-s", "--unix-socket", root.sock, "http://d/focus/" + path];
        actionProc.running = true;
    }

    function startFocus(secs) {
        var url = "http://d/focus/start?duration=" + secs;
        var lbl = labelField.text.trim();
        if (lbl.length > 0) url += "&label=" + encodeURIComponent(lbl);
        actionProc.command = ["curl", "-s", "--unix-socket", root.sock, url];
        actionProc.running = true;
        labelField.text = "";
        minutesField.text = "";
        root.popupOpen = false;
    }

    function startCustom() {
        var m = parseInt(minutesField.text, 10);
        if (m > 0) root.startFocus(m * 60);
    }

    Timer { // refresh while open
        interval: 2000
        running: root.popupOpen
        repeat: true
        onTriggered: stateProc.running = true
    }

    Timer { // local countdown tick
        interval: 1000
        running: root.popupOpen && root.active && !root.paused
        repeat: true
        onTriggered: {
            if (root.endAt > 0)
                root.remaining = Math.max(0, Math.round(root.endAt - Date.now() / 1000));
        }
    }

    // -- UI ------------------------------------------------------------------

    Item {
        anchors.fill: parent
        clip: true

        Item {
            anchors.fill: parent
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface { anchors.fill: parent }

            Column {
                id: mainCol
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // Header
                Item {
                    width: parent.width
                    height: 22
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: " Focus"
                        color: Helpers.Colors.accent
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeMedium
                        font.bold: true
                    }
                    Text {
                        visible: !root.active
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "ready"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    }
                    Rectangle {
                        visible: root.active
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 22
                        radius: 5
                        color: hdrPause.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                        Text {
                            anchors.centerIn: parent
                            text: root.paused ? "\uf04b" : "\uf04c"   // play / pause
                            color: root.paused ? Helpers.Colors.accent : Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        }
                        MouseArea {
                            id: hdrPause
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.action(root.paused ? "resume" : "pause")
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                // ── Active session view ──────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: root.active

                    Text {
                        width: parent.width
                        text: root.label.length > 0 ? root.label : "Focus session"
                        color: Helpers.Colors.textDefault
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.fmt(root.remaining)
                        color: root.paused ? Helpers.Colors.textMuted : Helpers.Colors.accent
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeDisplay
                        font.bold: true
                    }

                    // progress
                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * (root.planned > 0 ? Math.max(0, Math.min(1, 1 - root.remaining / root.planned)) : 0)
                            color: Helpers.Colors.accent
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 30
                        radius: 6
                        color: hovC.containsMouse ? Qt.rgba(0.96, 0.24, 0.24, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                        Text {
                            anchors.centerIn: parent
                            text: "\uf00d Cancel"
                            color: hovC.containsMouse ? Helpers.Colors.mutedRed : Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        }
                        MouseArea {
                            id: hovC
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.action("stop")
                        }
                    }
                }

                // ── Start view ───────────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: !root.active

                    Rectangle {
                        width: parent.width
                        height: 32
                        radius: 6
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: labelField.activeFocus ? Helpers.Colors.accent : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        TextField {
                            id: labelField
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "Goal (optional)"
                            color: Helpers.Colors.textDefault
                            placeholderTextColor: Helpers.Colors.textMuted
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            background: Item {}
                            onAccepted: root.startFocus(1500)
                        }
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.presets
                            Rectangle {
                                required property var modelData
                                width: (root.width - 32 - 8 * 2) / 3
                                height: 34
                                radius: 6
                                color: presetHov.containsMouse ? Qt.rgba(0.05, 0.69, 0.29, 0.30) : Qt.rgba(1, 1, 1, 0.06)
                                border.color: presetHov.containsMouse ? Helpers.Colors.accent : "transparent"
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: presetHov.containsMouse ? Helpers.Colors.accent : Helpers.Colors.textDefault
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
                                    font.bold: true
                                }
                                MouseArea {
                                    id: presetHov
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.startFocus(modelData.secs)
                                }
                            }
                        }
                    }

                    // custom duration
                    Row {
                        width: parent.width
                        spacing: 8
                    
                        Rectangle {
                            width: parent.width - 8 - 72
                            height: 32
                            radius: 6
                            color: Qt.rgba(1, 1, 1, 0.06)
                            border.color: minutesField.activeFocus ? Helpers.Colors.accent : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            TextField {
                                id: minutesField
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                verticalAlignment: TextInput.AlignVCenter
                                placeholderText: "Custom minutes"
                                color: Helpers.Colors.textDefault
                                placeholderTextColor: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                inputMethodHints: Qt.ImhDigitsOnly
                                validator: IntValidator { bottom: 1; top: 600 }
                                background: Item {}
                                onAccepted: root.startCustom()
                            }
                        }
                    
                        Rectangle {
                            width: 72
                            height: 32
                            radius: 6
                            opacity: (parseInt(minutesField.text, 10) > 0) ? 1 : 0.4
                            color: startHov.containsMouse ? Qt.rgba(0.05, 0.69, 0.29, 0.30) : Qt.rgba(1, 1, 1, 0.06)
                            border.color: startHov.containsMouse ? Helpers.Colors.accent : "transparent"
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Start"
                                color: startHov.containsMouse ? Helpers.Colors.accent : Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                font.bold: true
                            }
                            MouseArea {
                                id: startHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.startCustom()
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

                // ── Recent sessions ──────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 5

                    Text {
                        text: "Recent"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        font.bold: true
                    }

                    Text {
                        visible: root.sessions.length === 0
                        text: "No sessions yet"
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    }

                    Repeater {
                        model: root.sessions
                        Row {
                            required property var modelData
                            width: parent.width
                            spacing: 8

                            Text {
                                width: 16
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    switch (modelData.status) {
                                    case "completed": return "";
                                    case "cancelled": return "";
                                    case "interrupted": return "";
                                    default: return "";
                                    }
                                }
                                color: {
                                    switch (modelData.status) {
                                    case "completed": return Helpers.Colors.accent;
                                    case "cancelled": return Helpers.Colors.mutedRed;
                                    default: return Helpers.Colors.textMuted;
                                    }
                                }
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.clock(modelData.start)
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                width: 40
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData.label && modelData.label.length > 0 ? modelData.label : "Focus"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                width: parent.width - 16 - 40 - 8 * 3 - 56
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.fmt(modelData.status === "completed" ? modelData.plannedSeconds : modelData.activeSeconds)
                                color: Qt.rgba(1, 1, 1, 0.6)
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                width: 56
                                horizontalAlignment: Text.AlignRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
