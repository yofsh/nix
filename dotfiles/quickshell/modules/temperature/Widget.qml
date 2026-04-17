import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers

Item {
    id: root
    implicitWidth: col.implicitWidth + 4
    implicitHeight: parent ? parent.height : 22

    // Configurable: which sensors to show (top, bottom)
    property string sensor0: "cpu"
    property string sensor1: "gpu"

    property string label0: ""
    property string path0: ""
    property string label1: ""
    property string path1: ""

    property bool hovered: false
    property bool popupOpen: false
    property int temp0: path0 && file0.path ? Math.round(parseInt(file0.text().trim()) / 1000) || 0 : 0
    property int temp1: path1 && file1.path ? Math.round(parseInt(file1.text().trim()) / 1000) || 0 : 0

    function tempColor(t) {
        if (t >= 85) return Helpers.Colors.temperatureCritical;
        if (t >= 70) return "#ff9800";
        return Helpers.Colors.textMuted;
    }

    // Maps sensor names to hwmon driver matches and preferred labels
    // sensor0/sensor1 values: cpu, gpu, nvme, wifi
    Process {
        id: detectProc
        command: ["bash", "-c", [
            "find_sensor() {",
            "  local want=\"$1\"",
            "  for hw in /sys/class/hwmon/hwmon*/; do",
            "    name=$(cat \"${hw}name\" 2>/dev/null)",
            "    case \"$want\" in",
            "      cpu) case \"$name\" in k10temp|coretemp|zenpower) ;; *) continue ;; esac ;;",
            "      gpu) case \"$name\" in nvidia*|nouveau*|amdgpu) ;; *) continue ;; esac ;;",
            "      nvme) case \"$name\" in nvme*) ;; *) continue ;; esac ;;",
            "      wifi) case \"$name\" in iwlwifi*|mt79*|ath*|rtw*) ;; *) continue ;; esac ;;",
            "      *) continue ;;",
            "    esac",
            "    for f in \"${hw}\"temp*_input; do",
            "      [ -f \"$f\" ] || continue",
            "      label_f=\"${f%_input}_label\"",
            "      label=$(cat \"$label_f\" 2>/dev/null || echo \"$name\")",
            "      case \"$label\" in",
            "        Tctl|Tdie|Package*|Core\\ 0|Composite|GPU*|edge) echo \"$f\"; return ;;",
            "      esac",
            "    done",
            "    # fallback: first temp input for this driver",
            "    for f in \"${hw}\"temp*_input; do",
            "      [ -f \"$f\" ] && echo \"$f\" && return",
            "    done",
            "  done",
            "}",
            "# fallback: if requested sensor not found, try any available",
            "find_any() {",
            "  local skip=\"$1\"",
            "  for try in cpu gpu nvme wifi; do",
            "    [ \"$try\" = \"$skip\" ] && continue",
            "    local r=$(find_sensor \"$try\")",
            "    [ -n \"$r\" ] && echo \"$try|$r\" && return",
            "  done",
            "}",
            "r0=$(find_sensor '" + root.sensor0 + "')",
            "if [ -n \"$r0\" ]; then echo '" + root.sensor0 + "|'\"$r0\"",
            "else",
            "  fb=$(find_any '" + root.sensor1 + "')",
            "  [ -n \"$fb\" ] && echo \"$fb\" || echo ''",
            "fi",
            "r1=$(find_sensor '" + root.sensor1 + "')",
            "if [ -n \"$r1\" ]; then echo '" + root.sensor1 + "|'\"$r1\"",
            "else",
            "  fb=$(find_any '" + root.sensor0 + "')",
            "  [ -n \"$fb\" ] && echo \"$fb\" || echo ''",
            "fi"
        ].join("\n")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                if (lines.length > 0 && lines[0]) {
                    var p0 = lines[0].split("|");
                    if (p0.length >= 2) {
                        root.label0 = p0[0].toUpperCase();
                        root.path0 = p0[1];
                    }
                }
                if (lines.length > 1 && lines[1]) {
                    var p1 = lines[1].split("|");
                    if (p1.length >= 2) {
                        root.label1 = p1[0].toUpperCase();
                        root.path1 = p1[1];
                    }
                }
            }
        }
    }

    FileView { id: file0; path: root.path0; blockLoading: true }
    FileView { id: file1; path: root.path1; blockLoading: true }

    Timer {
        interval: 2000
        running: root.path0 !== ""
        repeat: true
        onTriggered: {
            if (root.path0) file0.reload();
            if (root.path1) file1.reload();
        }
    }

    Column {
        id: col
        anchors.centerIn: parent
        spacing: -2

        Text {
            visible: root.path0 !== ""
            text: (root.hovered ? root.label0 + " " : "") + (root.temp0 > 0 ? root.temp0 + "°" : "--")
            color: root.temp0 > 0 ? root.tempColor(root.temp0) : Helpers.Colors.textMuted
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 9
        }

        Text {
            visible: root.path1 !== ""
            text: (root.hovered ? root.label1 + " " : "") + (root.temp1 > 0 ? root.temp1 + "°" : "--")
            color: root.temp1 > 0 ? root.tempColor(root.temp1) : Helpers.Colors.textMuted
            font.family: "DejaVuSansM Nerd Font"
            font.pixelSize: 9
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.popupOpen = !root.popupOpen
        onEntered: root.hovered = true
        onExited: root.hovered = false
    }
}
