import QtQuick
import "../../config" as AppConfig
import "../../core" as Core
import "../cpu" as M_cpu
import "../gpu" as M_gpu
import "../system" as M_system
import "../temperature" as M_temperature

Item {
    id: root
    implicitWidth: groupRow.implicitWidth + 8
    implicitHeight: parent ? parent.height : 26

    property var screen: null
    property string registeredScreen: ""

    function screenName() {
        return screen && screen.name ? screen.name : "global";
    }

    function registerChildren() {
        var sn = screenName();
        if (registeredScreen === sn) return;
        if (registeredScreen) {
            Core.ModuleRegistry.unregisterWidgetInstance("cpu", registeredScreen);
            Core.ModuleRegistry.unregisterWidgetInstance("system", registeredScreen);
            Core.ModuleRegistry.unregisterWidgetInstance("temperature", registeredScreen);
        }
        Core.ModuleRegistry.registerWidgetInstance("cpu", sn, cpuWidget);
        Core.ModuleRegistry.registerWidgetInstance("system", sn, systemWidget);
        Core.ModuleRegistry.registerWidgetInstance("temperature", sn, tempWidget);
        registeredScreen = sn;
    }

    onScreenChanged: registerChildren()
    Component.onCompleted: registerChildren()

    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius
        color: Qt.rgba(0.9, 0.55, 0.1, 0.12)
    }

    Row {
        id: groupRow
        anchors.centerIn: parent
        height: parent.height
        spacing: AppConfig.Config.theme.spacingSmall

        // Statically imported (not Loader { source }) so the hot-reload
        // watcher follows these modules' files.
        M_cpu.Widget {
            id: cpuWidget
            height: parent.height
        }

        M_gpu.Widget {
            height: parent.height
        }

        M_system.Widget {
            id: systemWidget
            height: parent.height
        }

        M_temperature.Widget {
            id: tempWidget
            height: parent.height
        }
    }

    Component.onDestruction: {
        if (registeredScreen) {
            Core.ModuleRegistry.unregisterWidgetInstance("cpu", registeredScreen);
            Core.ModuleRegistry.unregisterWidgetInstance("system", registeredScreen);
            Core.ModuleRegistry.unregisterWidgetInstance("temperature", registeredScreen);
        }
    }
}
