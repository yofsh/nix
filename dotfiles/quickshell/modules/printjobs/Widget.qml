import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Print-queue widget. Pure consumer of the daemon's `cups/stream` (D-Bus-driven,
// see qs-daemon.d/modules/cups.ts). Collapses to zero width when the queue is
// empty, so it's invisible unless something is queued.
Item {
    id: root

    property var context: null
    property bool popupOpen: false

    property int count: 0
    property var jobs: []

    visible: root.count > 0
    implicitWidth: root.visible ? content.implicitWidth + 8 : 0
    implicitHeight: parent ? parent.height : 30

    Helpers.DaemonStream {
        path: "/cups/stream"
        onLine: data => {
            root.count = data.count || 0;
            root.jobs = data.jobs || [];
        }
    }

    Components.IconLabel {
        id: content
        anchors.centerIn: parent
        icon: ""                       // nf-fa-print
        label: root.count > 0 ? String(root.count) : ""
        iconColor: Helpers.Colors.accent
        boldLabel: true
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.popupOpen = !root.popupOpen
    }
}
