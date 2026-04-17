import QtQuick
import "../../config" as AppConfig
import "../../Core" as Core

Item {
    id: root
    property var context: null

    property int pingServiceRevision: Core.ModuleRegistry.serviceRevision
    readonly property var pingService: {
        pingServiceRevision;
        return Core.ModuleRegistry.serviceInstance("ping");
    }

    implicitWidth: loader.item ? loader.item.implicitWidth : 0
    implicitHeight: parent ? parent.height : 30

    Loader {
        id: loader
        source: "../ping/Widget.qml"
        anchors.fill: parent
        onLoaded: {
            item.target = Qt.binding(function() { return AppConfig.Config.network.gatewayTarget; });
            item.active = Qt.binding(function() { return root.pingService ? root.pingService.active : true; });
        }
    }
}
