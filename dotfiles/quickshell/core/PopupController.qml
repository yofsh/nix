import QtQuick
import "." as Core

QtObject {
    id: root

    property string moduleId: ""
    property var screen: null

    readonly property string screenName: screen && screen.name ? screen.name : "global"

    function isOpen() {
        var widget = Core.ModuleRegistry.widgetInstance(moduleId, screenName);
        if (widget && "popupOpen" in widget)
            return !!widget.popupOpen;

        return Core.PopupService.isOpen(moduleId, screenName);
    }

    function setOpen(open) {
        var nextOpen = !!open;

        var widget = Core.ModuleRegistry.widgetInstance(moduleId, screenName);
        if (widget && "popupOpen" in widget)
            widget.popupOpen = nextOpen;

        Core.PopupService.setOpen(moduleId, screenName, nextOpen);
    }

    function open() {
        setOpen(true);
    }

    function close() {
        setOpen(false);
    }

    function toggle() {
        setOpen(!isOpen());
    }
}
