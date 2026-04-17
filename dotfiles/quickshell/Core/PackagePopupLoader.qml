import QtQuick
import Quickshell.Hyprland
import "." as Core

Item {
    id: root

    required property string moduleId
    required property var screen
    required property var barWindow

    property var context: ModuleContext {
        moduleId: root.moduleId
        screen: root.screen
    }
    readonly property string screenName: screen && screen.name ? screen.name : "global"
    property int popupRevision: Core.PopupService.revision

    property int widgetRevision: Core.ModuleRegistry.widgetRevision
    readonly property var widget: {
        widgetRevision;
        return Core.ModuleRegistry.widgetInstance(moduleId, screenName);
    }

    readonly property bool widgetDrivesPopup: widget && "popupOpen" in widget

    function isOpen() {
        popupRevision;

        if (widgetDrivesPopup)
            return !!widget.popupOpen;

        return Core.PopupService.isOpen(moduleId, screenName);
    }

    function syncPopupState() {
        if (!loader.item || !("popupOpen" in loader.item))
            return;
        loader.item.popupOpen = isOpen();
    }

    function closePopup() {
        if (loader.item && typeof loader.item.closePopup === "function") {
            loader.item.closePopup();
            return;
        }

        if (loader.item && typeof loader.item.revertAndClose === "function") {
            loader.item.revertAndClose();
            return;
        }

        if (widgetDrivesPopup)
            widget.popupOpen = false;

        Core.PopupService.close(moduleId, screenName);

        syncPopupState();
    }

    Loader {
        id: loader
        active: source !== ""
        source: Core.ModuleRegistry.entryUrl(moduleId, "popup")
        asynchronous: true

        onLoaded: {
            if ("context" in item)
                item.context = root.context;
            if ("screen" in item)
                item.screen = root.screen;
            if ("barHeight" in item)
                item.barHeight = root.context.theme.barHeight || 22;
            root.syncPopupState();
        }
    }

    Connections {
        target: widget
        ignoreUnknownSignals: true

        function onPopupOpenChanged() {
            root.syncPopupState();
            Core.PopupService.setOpen(root.moduleId, root.screenName, !!root.widget.popupOpen);
        }
    }

    Connections {
        target: Core.PopupService

        function onRevisionChanged() {
            root.syncPopupState();
        }
    }

    HyprlandFocusGrab {
        windows: loader.item ? [barWindow, loader.item] : [barWindow]
        active: loader.item && root.isOpen()
        onCleared: root.closePopup()
    }
}
