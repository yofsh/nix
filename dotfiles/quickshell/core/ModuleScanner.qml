import Quickshell
import Quickshell.Io
import QtQuick
import "." as Core

Scope {
    id: root

    property string quickshellRoot: Qt.resolvedUrl("..").toString().replace("file://", "")
    property string scanCommand: [
        "for dir in \"" + root.quickshellRoot + "/modules/\"*/; do",
        "  [ -d \"$dir\" ] || continue",
        "  id=$(basename \"$dir\")",
        "  w=false; p=false; s=false",
        "  [ -f \"$dir/Widget.qml\" ] && w=true",
        "  [ -f \"$dir/Popup.qml\" ] && p=true",
        "  [ -f \"$dir/Service.qml\" ] && s=true",
        "  reldir=$(echo \"$dir\" | sed \"s|^" + root.quickshellRoot + "/||; s|/$||\")",
        "  echo \"${id}|${w}|${p}|${s}|${reldir}\"",
        "done"
    ].join("\n")

    function scan() {
        if (scanProc.running)
            return;
        scanProc.running = true;
    }

    Process {
        id: scanProc
        command: ["bash", "-lc", root.scanCommand]
        running: false
        stdout: StdioCollector {
            onStreamFinished: Core.ModuleRegistry.parseScanOutput(this.text)
        }
    }

    Component.onCompleted: Qt.callLater(root.scan)
}
