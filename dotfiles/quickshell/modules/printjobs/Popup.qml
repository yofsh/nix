import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../helpers/Format.js" as Format

// Content only — Core.PackagePopup provides the window, placement, open/close
// state, click-out and IPC. Lists the active CUPS jobs with per-job cancel.
Item {
    id: root

    property var context: null
    property bool popupOpen: false

    property int count: 0
    property var jobs: []

    implicitWidth: 360
    implicitHeight: Math.min(96 + Math.max(root.jobs.length, 1) * 52, 460)

    // Same stream as the widget — the popup stays live while open or closed.
    Helpers.DaemonStream {
        path: "/cups/stream"
        onLine: data => {
            root.count = data.count || 0;
            root.jobs = data.jobs || [];
        }
    }

    // Cancel actions hit the daemon's GET route, which returns fresh state.
    Helpers.DaemonFetch {
        id: actionFetch
        fetchOnActive: false
        onJson: data => {
            root.count = data.count || 0;
            root.jobs = data.jobs || [];
        }
    }
    function cancelJob(id) {
        actionFetch.path = "/cups/cancel?id=" + encodeURIComponent(id);
        actionFetch.reload();
    }
    function cancelAll() {
        actionFetch.path = "/cups/cancel?all=1";
        actionFetch.reload();
    }

    function jobNum(id) {
        var parts = String(id).split("-");
        return parts[parts.length - 1];
    }

    Components.PopupSurface { anchors.fill: parent }

    Components.PopupFlick {
        anchors.fill: parent
        anchors.margins: 16

        Components.PopupHeader {
            title: "  Print queue"
            Components.ActionButton {
                label: "Cancel all"
                visible: root.jobs.length > 0
                highlight: Helpers.Colors.mutedRed
                onClicked: root.cancelAll()
            }
        }

        Components.Divider {}

        Components.ThemedText {
            visible: root.jobs.length === 0
            muted: true
            text: "No active jobs"
        }

        Repeater {
            model: root.jobs

            Item {
                id: row
                required property var modelData
                width: parent ? parent.width : 0
                implicitHeight: 44

                Column {
                    anchors.left: parent.left
                    anchors.right: cancelBtn.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Components.ThemedText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: row.modelData.printer
                    }
                    Components.ThemedText {
                        width: parent.width
                        elide: Text.ElideRight
                        muted: true
                        font.pixelSize: 11
                        text: "#" + root.jobNum(row.modelData.id)
                              + "  ·  " + Format.bytes(row.modelData.size)
                              + "  ·  " + row.modelData.user
                    }
                }

                Components.ActionButton {
                    id: cancelBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    label: "Cancel"
                    highlight: Helpers.Colors.mutedRed
                    onClicked: root.cancelJob(row.modelData.id)
                }
            }
        }
    }
}
