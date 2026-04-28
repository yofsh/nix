import QtQuick
import "." as Core

Item {
    id: root

    required property string moduleId
    required property var screen

    property var context: ModuleContext {
        moduleId: root.moduleId
        screen: root.screen
    }

    readonly property var pkg: Core.ModuleRegistry.packageById(root.moduleId)
    readonly property var theme: Core.ConfigService.section("theme", {})
    readonly property var loadedItem: loader.item
    readonly property bool interactive: {
        if (loadedItem && "interactive" in loadedItem)
            return !!loadedItem.interactive;
        return pkg ? pkg.hasPopup : false;
    }
    readonly property bool hoverActive: interactive && hoverHandler.hovered && width > 0 && height > 0

    implicitWidth: loadedItem ? (loadedItem.implicitWidth || 0) : 0
    implicitHeight: parent ? parent.height : (loadedItem ? (loadedItem.implicitHeight || 0) : 0)
    width: loadedItem ? (loadedItem.implicitWidth || 0) : 0
    height: parent ? parent.height : (loadedItem ? (loadedItem.implicitHeight || 0) : 0)

    function screenName() {
        return screen && screen.name ? screen.name : "global";
    }

    function syncCommonProperties() {
        if (!loader.item)
            return;

        if ("context" in loader.item)
            loader.item.context = root.context;
        if ("screen" in loader.item)
            loader.item.screen = root.screen;
    }

    Rectangle {
        anchors.fill: parent
        radius: theme.interactiveHoverRadius || 4
        color: theme.interactiveHoverColor || "#14ffffff"
        opacity: root.hoverActive ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: theme.interactiveHoverDuration || 120
                easing.type: Easing.OutCubic
            }
        }
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: source !== ""
        source: Core.ModuleRegistry.entryUrl(root.moduleId, "widget")
        asynchronous: true

        onLoaded: {
            root.syncCommonProperties();
            Core.ModuleRegistry.registerWidgetInstance(root.moduleId, root.screenName(), item);
        }
    }

    Connections {
        target: loader

        function onItemChanged() {
            root.syncCommonProperties();
        }
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    Component.onDestruction: Core.ModuleRegistry.unregisterWidgetInstance(moduleId, screenName())
}
