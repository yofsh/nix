import QtQuick
import QtQuick.Controls

// Standard scrollable popup body: Flickable + as-needed scrollbar wrapping a
// Column. Children land in the Column.
//
//   Components.PopupFlick {
//       anchors.fill: parent
//       anchors.margins: 16
//       Components.PopupHeader { title: "..." }
//       // ...sections...
//   }
Flickable {
    id: root

    default property alias content: column.data
    property alias spacing: column.spacing

    contentWidth: width
    contentHeight: column.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
    }

    Column {
        id: column
        width: root.width
        spacing: 12
    }
}
