import QtQuick

Item {
    id: root
    property bool active: true
    implicitWidth: pingWidget.implicitWidth
    implicitHeight: parent ? parent.height : 30

    Ping {
        id: pingWidget
        target: "hermes"
        active: root.active
        anchors.fill: parent
    }
}
