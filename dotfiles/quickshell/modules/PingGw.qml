import QtQuick

Item {
    id: root
    implicitWidth: pingWidget.implicitWidth
    implicitHeight: parent ? parent.height : 30

    Ping {
        id: pingWidget
        target: "hermes"
        anchors.fill: parent
    }
}
