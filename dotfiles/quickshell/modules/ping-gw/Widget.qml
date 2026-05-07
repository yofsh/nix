import QtQuick
import "../../config" as AppConfig
import "../../core" as Core
import "../../helpers" as Helpers

Item {
    id: root
    property var context: null
    property var config: Helpers.ModuleConfig.resolve("ping-gw")

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
            item.context = root.context;
            item.target = Qt.binding(function() { return AppConfig.Config.network.gatewayTarget; });
            item.active = Qt.binding(function() {
                return root.pingService ? root.pingService.active
                    : root.config.defaultActive;
            });
            item.pingInterval = Qt.binding(function() {
                return root.pingService ? root.pingService.pingInterval
                    : root.config.interval;
            });
        }
    }
}
