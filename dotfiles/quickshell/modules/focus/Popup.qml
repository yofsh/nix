import Quickshell
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
        if (popupOpen)
            autofocusTimer.restart();
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

    Helpers.DaemonFetch { // state, refreshed every 2s while open
        path: "/focus/state"
        active: root.popupOpen
        intervalMs: 2000
        onJson: data => root.applyState(data)
    }

    Helpers.DaemonFetch {
        id: historyFetch
        path: "/focus/history?limit=12"
        active: root.popupOpen
        onJson: data => { root.sessions = data.sessions || []; }
    }

    Helpers.DaemonFetch {
        id: actionFetch
        fetchOnActive: false
        onJson: data => {
            root.applyState(data);
            historyFetch.reload();
        }
        onFailed: historyFetch.reload()
    }

    function action(path) {
        actionFetch.path = "/focus/" + path;
        actionFetch.reload();
    }

    function startFocus(secs) {
        var url = "/focus/start?duration=" + secs;
        var lbl = labelField.text.trim();
        if (lbl.length > 0) url += "&label=" + encodeURIComponent(lbl);
        actionFetch.path = url;
        actionFetch.reload();
        labelField.text = "";
        minutesField.text = "";
        root.popupOpen = false;
    }

    function startCustom() {
        var m = parseInt(minutesField.text, 10);
        if (m > 0) root.startFocus(m * 60);
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
                Components.PopupHeader {
                    title: " Focus"
                    Components.ThemedText {
                        visible: !root.active
                        text: "ready"
                        muted: true
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    }
                    Rectangle {
                        visible: root.active
                        width: 30
                        height: 22
                        radius: 5
                        color: hdrPause.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                        Components.ThemedText {
                            anchors.centerIn: parent
                            text: root.paused ? "\uf04b" : "\uf04c"   // play / pause
                            color: root.paused ? Helpers.Colors.accent : Helpers.Colors.textDefault
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

                Components.Divider {}

                // ── Active session view ──────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 10
                    visible: root.active

                    Components.ThemedText {
                        width: parent.width
                        text: root.label.length > 0 ? root.label : "Focus session"
                        elide: Text.ElideRight
                    }

                    Components.ThemedText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.fmt(root.remaining)
                        color: root.paused ? Helpers.Colors.textMuted : Helpers.Colors.accent
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
                        Components.ThemedText {
                            anchors.centerIn: parent
                            text: "\uf00d Cancel"
                            color: hovC.containsMouse ? Helpers.Colors.mutedRed : Helpers.Colors.textDefault
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
                            Components.ActionButton {
                                required property var modelData
                                width: (root.width - 32 - 8 * 2) / 3
                                height: 34
                                label: modelData.label
                                onClicked: root.startFocus(modelData.secs)
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
                    
                        Components.ActionButton {
                            width: 72
                            height: 32
                            label: "Start"
                            fontSize: AppConfig.Config.theme.popupFontSizeSmall
                            opacity: (parseInt(minutesField.text, 10) > 0) ? 1 : 0.4
                            onClicked: root.startCustom()
                        }
                    }
                }

                Components.Divider {}

                // ── Recent sessions ──────────────────────────────────────
                Column {
                    width: parent.width
                    spacing: 5

                    Components.SectionLabel { text: "Recent" }

                    Components.ThemedText {
                        visible: root.sessions.length === 0
                        text: "No sessions yet"
                        muted: true
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    }

                    Repeater {
                        model: root.sessions
                        Row {
                            required property var modelData
                            width: parent.width
                            spacing: 8

                            Components.ThemedText {
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
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Components.ThemedText {
                                text: root.clock(modelData.start)
                                muted: true
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                width: 40
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Components.ThemedText {
                                text: modelData.label && modelData.label.length > 0 ? modelData.label : "Focus"
                                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                                width: parent.width - 16 - 40 - 8 * 3 - 56
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Components.ThemedText {
                                text: root.fmt(modelData.status === "completed" ? modelData.plannedSeconds : modelData.activeSeconds)
                                color: Qt.rgba(1, 1, 1, 0.6)
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
