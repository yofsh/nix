import QtQuick
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "../../core" as Core

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
        if (cpuLoader.item)
            Core.ModuleRegistry.registerWidgetInstance("cpu", sn, cpuLoader.item);
        if (systemLoader.item)
            Core.ModuleRegistry.registerWidgetInstance("system", sn, systemLoader.item);
        if (tempLoader.item)
            Core.ModuleRegistry.registerWidgetInstance("temperature", sn, tempLoader.item);
        registeredScreen = sn;
    }

    onScreenChanged: registerChildren()

    Rectangle {
        anchors.fill: parent
        radius: AppConfig.Config.theme.interactiveHoverRadius || 4
        color: Qt.rgba(0.9, 0.55, 0.1, 0.12)
    }

    Row {
        id: groupRow
        anchors.centerIn: parent
        height: parent.height
        spacing: AppConfig.Config.theme.spacingSmall || 4

        Loader {
            id: cpuLoader
            height: parent.height
            source: "../cpu/Widget.qml"
            onLoaded: root.registerChildren()
        }

        Loader {
            height: parent.height
            source: "../gpu/Widget.qml"
        }

        Loader {
            id: systemLoader
            height: parent.height
            source: "../system/Widget.qml"
            onLoaded: root.registerChildren()
        }

        Loader {
            id: tempLoader
            height: parent.height
            source: "../temperature/Widget.qml"
            onLoaded: root.registerChildren()
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
