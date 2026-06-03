import Quickshell
import QtQuick
import "." as Core
import "../helpers" as Helpers

// Registers a module's Service.qml instance so `context.service` resolves for its
// widgets, and wires the service's context/config. The service object is passed as
// the declared child. Popup open/close IPC lives in PackagePopup, so popup-only
// modules don't need a service at all.
//
//   Core.PackageService { moduleId: "network"; M_network.Service {} }
Item {
    id: root

    required property string moduleId
    property var service: null

    readonly property var context: Core.ModuleContext {
        moduleId: root.moduleId
        screen: null
    }

    Component.onCompleted: {
        service = root.data.length > 0 ? root.data[0] : null;
        if (!service)
            return;
        if ("context" in service)
            service.context = root.context;
        if (Helpers.ModuleConfig.has(moduleId) && "config" in service)
            service.config = Qt.binding(function() { return root.context.config; });
        Core.ModuleRegistry.registerServiceInstance(moduleId, service);
    }

    Component.onDestruction: Core.ModuleRegistry.unregisterServiceInstance(moduleId)
}
