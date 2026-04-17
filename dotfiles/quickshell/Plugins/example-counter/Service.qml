import Quickshell
import QtQuick

Scope {
    id: root

    property var context
    property int value: 0

    Timer {
        interval: root.context ? (root.context.config.intervalMs || 1000) : 1000
        running: true
        repeat: true
        onTriggered: root.value += 1
    }
}
