import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "modules" as Modules
import "helpers" as Helpers

Scope {
    id: root
    property bool networkPinned: false

    IpcHandler {
        target: "network"
        function toggle(): void { root.networkPinned = !root.networkPinned; }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWindow
            required property var modelData
            screen: modelData

            property string submapName: ""
            property var submapBinds: []  // [{combo, desc}]
            property real submapComboWidth: 0
            property var keybindsData: null

            anchors {
                top: true
                left: true
                right: true
            }

            margins.top: 0
            color: "transparent"
            implicitHeight: 22

            Process {
                id: keybindsProc
                command: ["hypr-keybinds"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            barWindow.keybindsData = JSON.parse(this.text);
                            barWindow.updateSubmapBinds();
                        } catch (e) {
                            console.warn("hypr-keybinds parse error:", e);
                        }
                    }
                }
            }

            // Hidden text for measuring combo column width
            Text {
                id: comboMeasure
                visible: false
                font.family: "DejaVuSansM Nerd Font"
                font.pixelSize: 12
                font.bold: true
            }

            function updateSubmapBinds() {
                if (!submapName || !keybindsData || !keybindsData.submaps)
                    return;  // keep old data for slide-out animation
                for (var i = 0; i < keybindsData.submaps.length; i++) {
                    var sm = keybindsData.submaps[i];
                    if (sm.name === submapName) {
                        var entries = [];
                        var maxW = 0;
                        for (var j = 0; j < sm.binds.length; j++) {
                            var sep = sm.binds[j].pretty.indexOf(" \u2014 ");
                            var combo = sep >= 0 ? sm.binds[j].pretty.substring(0, sep) : sm.binds[j].pretty;
                            var desc = sep >= 0 ? sm.binds[j].pretty.substring(sep + 3) : "";
                            comboMeasure.text = combo;
                            if (comboMeasure.implicitWidth > maxW)
                                maxW = comboMeasure.implicitWidth;
                            entries.push({combo: combo, desc: desc});
                        }
                        submapBinds = entries;
                        submapComboWidth = maxW;
                        return;
                    }
                }
            }

            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (event.name === "submap") {
                        barWindow.submapName = event.data.trim();
                        barWindow.updateSubmapBinds();
                        if (barWindow.submapName)
                            keybindsProc.running = true;
                    }
                }
            }

            // Entire bar content at 50% opacity to match waybar
            Item {
                id: barContent
                anchors.centerIn: parent
                width: barRow.implicitWidth + 16
                height: parent.height
                opacity: 0.8

                Rectangle {
                    anchors.fill: parent
                    color: "#11000000"
                    radius: 16
                }

                Row {
                    id: barRow
                    anchors.centerIn: parent
                    spacing: 8
                    height: parent.height

                    Modules.WindowTitle { screen: barWindow.screen }
                    Modules.Workspaces {}
                    // Modules.WfRecorder {}
                    Modules.Yts {}
                    Modules.Media {}
                    Modules.Backlight {}
                    Modules.Volume {}
                    Modules.Network { pinned: root.networkPinned }
                    // Modules.PingGw {}
                    // Modules.Ping {}
                    Modules.Cpu {}
                    Modules.Memory {}
                    Modules.Temperature {}
                    Modules.Battery { id: batteryModule }
                    Modules.AirPods {}
                    Modules.PowerProfile {}
                    Modules.Clock {}
                    Modules.HeadsetBattery {}
                    Modules.Language {}
                    Modules.Dunst {}
                    Modules.SysTray {}
                }
            }

            Modules.OsdPopup { screen: barWindow.screen; barHeight: barWindow.implicitHeight }
            Modules.FingerprintPopup { screen: barWindow.screen; barHeight: barWindow.implicitHeight }
            Modules.BatteryPopup { id: batteryPopup; screen: barWindow.screen; barHeight: barWindow.implicitHeight; popupOpen: batteryModule.popupOpen }

            HyprlandFocusGrab {
                windows: [barWindow, batteryPopup]
                active: batteryModule.popupOpen
                onCleared: batteryModule.popupOpen = false
            }

            PanelWindow {
                id: submapPopup
                screen: barWindow.screen
                anchors.top: true
                exclusionMode: ExclusionMode.Ignore
                margins.top: barWindow.implicitHeight
                implicitWidth: submapPopupCol.width + 32
                implicitHeight: submapPopupCol.height + 16
                visible: barWindow.submapName !== "" || submapAnim.running
                color: "transparent"

                Item {
                    anchors.fill: parent
                    clip: true

                    Item {
                        id: submapContent
                        width: parent.width
                        height: parent.height
                        y: -parent.height
                        opacity: 0.8

                        states: State {
                            name: "visible"; when: barWindow.submapName !== ""
                            PropertyChanges { target: submapContent; y: 0 }
                        }

                        transitions: Transition {
                            id: submapAnim
                            NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic }
                        }

                        Item {
                            anchors.fill: parent
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: -16
                                color: "#11000000"
                                radius: 16
                            }
                        }

                        Column {
                            id: submapPopupCol
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                id: submapLabel
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: barWindow.submapName
                                color: Helpers.Colors.textDefault
                                font.family: "DejaVuSansM Nerd Font"
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Repeater {
                                model: barWindow.submapBinds
                                Row {
                                    spacing: 8
                                    Text {
                                        width: barWindow.submapComboWidth
                                        horizontalAlignment: Text.AlignRight
                                        text: modelData.combo
                                        color: Helpers.Colors.textDefault
                                        font.family: "DejaVuSansM Nerd Font"
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                    Text {
                                        text: modelData.desc
                                        color: Helpers.Colors.textMuted
                                        font.family: "DejaVuSansM Nerd Font"
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
