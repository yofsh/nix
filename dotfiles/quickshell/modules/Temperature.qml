import QtQuick
import Quickshell.Io
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: tempText.implicitWidth + 4
    implicitHeight: parent ? parent.height : 30

    property string sensorPath: ""
    property string sensorLabel: ""
    property int tempC: {
        if (!sensorPath) return 0;
        var raw = tempFile.text().trim();
        return raw ? Math.round(parseInt(raw) / 1000) : 0;
    }
    property bool isCritical: tempC >= 75

    Process {
        id: detectProc
        command: ["bash", "-c", [
            "for hw in /sys/class/hwmon/hwmon*/; do",
            "  name=$(cat \"${hw}name\" 2>/dev/null)",
            "  case \"$name\" in",
            "    k10temp|coretemp|zenpower)",
            "      for f in \"${hw}\"temp*_input; do",
            "        [ -f \"$f\" ] || continue",
            "        label_f=\"${f%_input}_label\"",
            "        label=$(cat \"$label_f\" 2>/dev/null || echo \"$name\")",
            "        echo \"${f}|${label}\"",
            "        exit 0",
            "      done",
            "      ;;",
            "  esac",
            "done",
            "for hw in /sys/class/hwmon/hwmon*/; do",
            "  for f in \"${hw}\"temp*_input; do",
            "    [ -f \"$f\" ] || continue",
            "    name=$(cat \"${hw}name\" 2>/dev/null || echo \"unknown\")",
            "    label_f=\"${f%_input}_label\"",
            "    label=$(cat \"$label_f\" 2>/dev/null || echo \"$name\")",
            "    echo \"${f}|${label}\"",
            "    exit 0",
            "  done",
            "done"
        ].join("\n")]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = this.text.trim().split("|");
                if (parts.length >= 2) {
                    root.sensorPath = parts[0];
                    root.sensorLabel = parts[1];
                }
            }
        }
    }

    FileView {
        id: tempFile
        path: root.sensorPath
        blockLoading: true
    }

    Text {
        id: tempText
        anchors.verticalCenter: parent.verticalCenter
        text: root.tempC > 0 ? root.tempC + "°" : ""
        color: root.isCritical ? Helpers.Colors.temperatureCritical : Helpers.Colors.textDefault
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 12
    }

    Timer {
        interval: 2000
        running: root.sensorPath !== ""
        repeat: true
        onTriggered: tempFile.reload()
    }
}
