import Quickshell
import Quickshell.Io
import QtQuick
import "." as Core

Item {
    id: root

    required property string moduleId

    readonly property var pkg: Core.ModuleRegistry.packageById(moduleId)
    readonly property bool hasCustomService: pkg && pkg.hasService
    readonly property bool hasPopup: pkg && pkg.hasPopup

    property var context: ModuleContext {
        moduleId: root.moduleId
        screen: null
    }

    // Load custom Service.qml if present
    Loader {
        id: serviceLoader
        active: root.hasCustomService
        source: root.hasCustomService ? Core.ModuleRegistry.entryUrl(root.moduleId, "service") : ""
        asynchronous: true

        function syncCommonProperties() {
            if (!item)
                return;
            if ("context" in item)
                item.context = root.context;
        }

        onLoaded: {
            syncCommonProperties();
            Core.ModuleRegistry.registerServiceInstance(root.moduleId, item);
        }

        onItemChanged: syncCommonProperties()
    }

    // Auto-IPC fallback for popup modules without a custom Service.qml
    Loader {
        id: autoIpcLoader
        active: !root.hasCustomService && root.hasPopup
        sourceComponent: Component {
            Scope {
                id: autoIpcScope

                IpcHandler {
                    target: root.moduleId

                    function toggle() {
                        if (root.context)
                            root.context.togglePopup();
                    }

                    function open() {
                        if (root.context)
                            root.context.openPopup();
                    }

                    function close() {
                        if (root.context)
                            root.context.closePopup();
                    }
                }

                Component.onCompleted: Core.ModuleRegistry.registerServiceInstance(root.moduleId, autoIpcScope)
            }
        }
    }

    Component.onDestruction: Core.ModuleRegistry.unregisterServiceInstance(moduleId)
}
