import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

// Content only — Core.PackagePopup provides window/placement/state/click-out/IPC.
Item {
    id: root
    property bool popupOpen: false

    implicitWidth: popupGrid.width + 40
    implicitHeight: popupGrid.height + 32

    property var sensorGroups: []

    onPopupOpenChanged: {
        if (popupOpen) sensorsProc.running = true;
    }

    Process {
        id: sensorsProc
        command: ["sensors", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseSensors(this.text)
        }
    }

    Timer {
        interval: 1000
        running: root.popupOpen
        repeat: true
        onTriggered: sensorsProc.running = true
    }

    function tempColor(t) {
        if (t >= 85) return Helpers.Colors.temperatureCritical;
        if (t >= 70) return "#ff9800";
        return Helpers.Colors.textDefault;
    }

    function readingColor(type, raw) {
        if (type === "temp") return tempColor(raw);
        if (type === "fan") return "#89b4fa";
        if (type === "power") return "#ff9800";
        return Helpers.Colors.textMuted;
    }

    function parseSensors(raw) {
        var data;
        try { data = JSON.parse(raw); } catch(e) { return; }

        var chipDefs = [
            { match: "zenpower", icon: "󰻠", label: "CPU", order: 0 },
            { match: "k10temp",  icon: "󰻠", label: "CPU", order: 0 },
            { match: "coretemp", icon: "󰻠", label: "CPU", order: 0 },
            { match: "amdgpu",   icon: "󰢮", label: "GPU", order: 1 },
            { match: "nvidia",   icon: "󰢮", label: "GPU", order: 1 },
            { match: "nvme",     icon: "󰋊", label: "NVMe", order: 2 },
            { match: "mt79",     icon: "󰖩", label: "WiFi", order: 3 },
            { match: "iwlwifi",  icon: "󰖩", label: "WiFi", order: 3 },
            { match: "ath",      icon: "󰖩", label: "WiFi", order: 3 },
            { match: "asusec",   icon: "󰍛", label: "Motherboard", order: 4 },
            { match: "spd5118",  icon: "", label: "RAM", order: 5 },
            { match: "nct6",     icon: "󰈐", label: "Fans", order: 6 },
            { match: "it87",     icon: "󰈐", label: "Fans", order: 6 },
        ];

        var groups = [];

        for (var chip in data) {
            var chipData = data[chip];
            var chipBase = chip.split("-")[0];

            var meta = null;
            for (var m = 0; m < chipDefs.length; m++) {
                if (chipBase.indexOf(chipDefs[m].match) === 0) {
                    meta = chipDefs[m];
                    break;
                }
            }
            if (!meta) continue;

            var isSuperIO = (meta.order === 6);
            var isGPU = (meta.order === 1);
            var readings = [];

            for (var sensor in chipData) {
                if (sensor === "Adapter") continue;
                var sData = chipData[sensor];
                if (typeof sData !== "object") continue;

                // Super I/O: skip noisy sensors
                if (isSuperIO) {
                    if (/^(AUXTIN|PCH|PECI|TSI|pwm|intrusion|beep|in\d)/.test(sensor)) continue;
                }

                for (var key in sData) {
                    var val = sData[key];
                    if (typeof val !== "number") continue;

                    if (/^temp\d+_input$/.test(key)) {
                        if (val <= 0 || val > 150) continue;
                        readings.push({ label: sensor, value: val.toFixed(1) + "°", type: "temp", raw: val });
                    } else if (/^fan\d+_input$/.test(key)) {
                        if (val <= 0) continue;
                        readings.push({ label: sensor, value: Math.round(val) + " RPM", type: "fan", raw: val });
                    } else if (/^power\d+_input$/.test(key)) {
                        readings.push({ label: sensor, value: val.toFixed(1) + " W", type: "power", raw: val });
                    } else if (/^freq\d+_input$/.test(key)) {
                        readings.push({ label: sensor, value: Math.round(val / 1000000) + " MHz", type: "freq", raw: val });
                    } else if (/^in\d+_input$/.test(key) && isGPU) {
                        readings.push({ label: sensor, value: val.toFixed(3) + " V", type: "volt", raw: val });
                    }
                }
            }

            if (readings.length === 0) continue;

            var parts = chip.split("-");
            var chipId = parts.length >= 3 ? parts[parts.length - 1] : "";

            groups.push({
                icon: meta.icon,
                label: meta.label,
                chipId: chipId,
                order: meta.order,
                readings: readings
            });
        }

        groups.sort(function(a, b) { return a.order - b.order; });
        sensorGroups = groups;
    }

    Item {
        anchors.fill: parent

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface {
                anchors.fill: parent
            }

            Grid {
                id: popupGrid
                anchors.centerIn: parent
                columns: 2
                columnSpacing: 28
                rowSpacing: 12

                Repeater {
                    model: root.sensorGroups

                    Column {
                        spacing: 1

                        // Group header
                        Row {
                            spacing: 6
                            Components.ThemedText {
                                text: modelData.icon
                                font.pixelSize: 14
                            }
                            Components.ThemedText {
                                text: modelData.label
                                font.pixelSize: 14
                                font.bold: true
                            }
                            Components.ThemedText {
                                text: modelData.chipId
                                muted: true
                                font.pixelSize: 14
                                visible: modelData.chipId !== ""
                                anchors.baseline: parent.children[1].baseline
                            }
                        }

                        // Readings
                        Repeater {
                            model: modelData.readings

                            Row {
                                spacing: 8
                                Components.ThemedText {
                                    width: 100
                                    text: modelData.label
                                    muted: true
                                    font.pixelSize: 14
                                    elide: Text.ElideRight
                                }
                                Components.ThemedText {
                                    width: 70
                                    text: modelData.value
                                    color: root.readingColor(modelData.type, modelData.raw)
                                    font.pixelSize: 14
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
