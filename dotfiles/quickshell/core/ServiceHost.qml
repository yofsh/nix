import Quickshell
import QtQuick
import "." as Core

Scope {
    Variants {
        model: Core.ModuleRegistry.ready ? Core.ModuleRegistry.serviceIds() : []

        Core.PackageServiceLoader {
            required property var modelData
            moduleId: modelData
        }
    }
}
