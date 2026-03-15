import QtQuick
import "../config" as AppConfig

Item {
    id: root
    property bool active: true
    implicitWidth: pingWidget.implicitWidth
    implicitHeight: parent ? parent.height : 30

    Ping {
        id: pingWidget
        target: AppConfig.Config.network.gatewayTarget
        active: root.active
        anchors.fill: parent
    }
}
