import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// Bottom-of-screen cheatsheet shown while a hyprland submap is active: the
// submap name plus a grid of its binds (combo right-aligned, description
// muted). Bind data comes from the qs-daemon keybinds cache and is re-fetched
// each time a submap activates. BarHost reads `submapName` to tint the bar.
PanelWindow {
    id: root

    property string submapName: ""
    property var binds: []
    property real comboWidth: 0
    property var keybindsData: null

    readonly property var theme: AppConfig.Config.theme
    // Noticeably larger fonts for the cheatsheet overlay
    readonly property int bindFontSize: Math.round(theme.fontSizeDefault * 1.5)
    readonly property int titleFontSize: Math.round(theme.fontSizeDefault * 1.9)

    anchors.bottom: true
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: bindsColumn.width + 32
    implicitHeight: bindsColumn.height + 16
    visible: submapName !== ""
    color: "transparent"

    function updateBinds() {
        if (!submapName || !keybindsData || !keybindsData.submaps)
            return;

        for (var i = 0; i < keybindsData.submaps.length; i++) {
            var submap = keybindsData.submaps[i];
            if (submap.name !== submapName)
                continue;

            var entries = [];
            var maxWidth = 0;

            for (var j = 0; j < submap.binds.length; j++) {
                var pretty = submap.binds[j].pretty || "";
                var separator = pretty.indexOf(" — ");
                var combo = separator >= 0 ? pretty.substring(0, separator) : pretty;
                var description = separator >= 0 ? pretty.substring(separator + 3) : "";

                comboMeasure.text = combo;
                if (comboMeasure.implicitWidth > maxWidth)
                    maxWidth = comboMeasure.implicitWidth;

                entries.push({ combo: combo, desc: description });
            }

            binds = entries;
            comboWidth = maxWidth;
            return;
        }
    }

    Process {
        id: keybindsProc
        command: ["curl", "-s", "--unix-socket", AppConfig.Config.daemon.socket, "http://d/keybinds/list"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.keybindsData = JSON.parse(this.text);
                    root.updateBinds();
                } catch (error) {
                    console.warn("hypr-keybinds parse error:", error);
                }
            }
        }
    }

    Text {
        id: comboMeasure
        visible: false
        font.family: root.theme.fontFamily
        font.pixelSize: root.bindFontSize
        font.bold: true
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "submap")
                return;

            root.submapName = event.data.trim();
            root.updateBinds();
            if (root.submapName)
                keybindsProc.running = true;
        }
    }

    Item {
        anchors.fill: parent
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.height + root.theme.surfaceRadius
            color: {
                var src = Qt.color(Helpers.Colors.submapBg);
                return Qt.rgba(src.r, src.g, src.b, src.a * root.theme.surfaceOpacity);
            }
            radius: root.theme.surfaceRadius
            antialiasing: true
            layer.enabled: true
            layer.samples: 8
            layer.smooth: true
        }

        Column {
            id: bindsColumn
            anchors.centerIn: parent
            spacing: root.theme.spacingMedium

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.submapName
                color: Helpers.Colors.submapFg
                font.family: root.theme.fontFamily
                font.pixelSize: root.titleFontSize
                font.bold: true
            }

            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: root.binds.length > 12 ? 3 : (root.binds.length > 5 ? 2 : 1)
                rowSpacing: root.theme.spacingSmall
                columnSpacing: root.theme.spacingDefault * 2
                flow: Grid.TopToBottom
                rows: Math.ceil(root.binds.length / columns)

                Repeater {
                    model: root.binds

                    Row {
                        spacing: root.theme.spacingDefault

                        Text {
                            width: root.comboWidth
                            horizontalAlignment: Text.AlignRight
                            text: modelData.combo
                            color: Helpers.Colors.submapFg
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.bindFontSize
                            font.bold: true
                        }

                        Text {
                            text: modelData.desc
                            color: Helpers.Colors.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.bindFontSize
                        }
                    }
                }
            }
        }
    }
}
