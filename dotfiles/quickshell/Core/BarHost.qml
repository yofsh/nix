//@ pragma IconTheme Papirus
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../helpers" as Helpers
import "../components" as Components
import "../popups" as Popups
import "." as Core

PanelWindow {
    id: barWindow

    required property var screen
    property bool polkitActive: false

    readonly property var theme: Core.ConfigService.section("theme", {})
    readonly property var hostScreenInfo: screen
    readonly property string hostScreenName: hostScreenInfo && hostScreenInfo.name ? hostScreenInfo.name : "global"
    property string submapName: ""
    property var submapBinds: []
    property real submapComboWidth: 0
    property var keybindsData: null

    anchors {
        top: true
        left: true
        right: true
    }

    margins.top: 0
    color: "transparent"
    implicitHeight: theme.barHeight || 22

    Process {
        id: keybindsProc
        command: ["hypr-keybinds"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    barWindow.keybindsData = JSON.parse(this.text);
                    barWindow.updateSubmapBinds();
                } catch (error) {
                    console.warn("hypr-keybinds parse error:", error);
                }
            }
        }
    }

    Text {
        id: comboMeasure
        visible: false
        font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
        font.pixelSize: theme.fontSizeDefault || 12
        font.bold: true
    }

    function updateSubmapBinds() {
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
                var separator = pretty.indexOf(" \u2014 ");
                var combo = separator >= 0 ? pretty.substring(0, separator) : pretty;
                var description = separator >= 0 ? pretty.substring(separator + 3) : "";

                comboMeasure.text = combo;
                if (comboMeasure.implicitWidth > maxWidth)
                    maxWidth = comboMeasure.implicitWidth;

                entries.push({ combo: combo, desc: description });
            }

            submapBinds = entries;
            submapComboWidth = maxWidth;
            return;
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "submap")
                return;

            barWindow.submapName = event.data.trim();
            barWindow.updateSubmapBinds();
            if (barWindow.submapName)
                keybindsProc.running = true;
        }
    }

    Item {
        id: barContent
        anchors.centerIn: parent
        width: Math.max(contentRow.implicitWidth, contentRow.childrenRect.width) + 16
        height: parent.height
        opacity: theme.surfaceOpacity || 0.8

        Rectangle {
            anchors.fill: parent
            color: theme.surfaceColor || "#11000000"
            radius: theme.surfaceRadius || 0
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: theme.spacingDefault || 8
            height: parent.height

            Row {
                id: leftSection
                spacing: theme.spacingDefault || 8
                width: implicitWidth
                height: parent.height

                Repeater {
                    model: Core.ModuleRegistry.ready ? Core.ModuleRegistry.barIds("left") : []

                    Core.PackageWidgetLoader {
                        required property var modelData
                        moduleId: modelData
                        screen: hostScreenInfo
                    }
                }
            }

            Row {
                id: centerSection
                spacing: theme.spacingDefault || 8
                visible: children.length > 0
                width: visible ? implicitWidth : 0
                height: parent.height

                Repeater {
                    model: Core.ModuleRegistry.ready ? Core.ModuleRegistry.barIds("center") : []

                    Core.PackageWidgetLoader {
                        required property var modelData
                        moduleId: modelData
                        screen: hostScreenInfo
                    }
                }
            }

            Row {
                id: rightSection
                spacing: theme.spacingDefault || 8
                width: implicitWidth
                height: parent.height

                Repeater {
                    model: Core.ModuleRegistry.ready ? Core.ModuleRegistry.barIds("right") : []

                    Core.PackageWidgetLoader {
                        required property var modelData
                        moduleId: modelData
                        screen: hostScreenInfo
                    }
                }
            }
        }
    }

    Repeater {
        model: Core.ModuleRegistry.ready ? Core.ModuleRegistry.popupIds() : []

        Core.PackagePopupLoader {
            required property var modelData
            moduleId: modelData
            screen: hostScreenInfo
            barWindow: barWindow
        }
    }

    Popups.NotificationPopup {
        id: notifPopup
        screen: hostScreenInfo
        barHeight: barWindow.implicitHeight

        Component.onCompleted: Core.ModuleRegistry.registerWindowInstance("notifications", hostScreenName, this)
        Component.onDestruction: Core.ModuleRegistry.unregisterWindowInstance("notifications", hostScreenName)
    }

    Popups.OsdPopup {
        screen: hostScreenInfo
        barHeight: barWindow.implicitHeight
    }

    Popups.FingerprintPopup {
        screen: hostScreenInfo
        barHeight: barWindow.implicitHeight
        polkitActive: barWindow.polkitActive
    }

    PanelWindow {
        id: submapPopup
        screen: hostScreenInfo
        anchors.bottom: true
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: submapPopupCol.width + 32
        implicitHeight: submapPopupCol.height + 16
        visible: barWindow.submapName !== ""
        color: "transparent"

        Item {
            anchors.fill: parent

            Item {
                id: submapContent
                width: parent.width
                height: parent.height
                opacity: theme.surfaceOpacity || 0.8

                Components.PopupSurface {
                    anchors.fill: parent
                }

                Column {
                    id: submapPopupCol
                    anchors.centerIn: parent
                    spacing: theme.spacingCompact || 2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: barWindow.submapName
                        color: Helpers.Colors.textDefault
                        font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
                        font.pixelSize: theme.fontSizeDefault || 12
                        font.bold: true
                    }

                    Repeater {
                        model: barWindow.submapBinds

                        Row {
                            spacing: theme.spacingDefault || 8

                            Text {
                                width: barWindow.submapComboWidth
                                horizontalAlignment: Text.AlignRight
                                text: modelData.combo
                                color: Helpers.Colors.textDefault
                                font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
                                font.pixelSize: theme.fontSizeDefault || 12
                                font.bold: true
                            }

                            Text {
                                text: modelData.desc
                                color: Helpers.Colors.textMuted
                                font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
                                font.pixelSize: theme.fontSizeDefault || 12
                            }
                        }
                    }
                }
            }
        }
    }
}
