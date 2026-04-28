import QtQuick
import "." as Core

QtObject {
    id: root

    property string moduleId: ""
    property var screen: null
    property int serviceRevision: Core.ModuleRegistry.serviceRevision
    readonly property var effectiveScreen: screen || Core.ScreenService.activeScreen
    readonly property string screenName: effectiveScreen && effectiveScreen.name ? effectiveScreen.name : "global"
    readonly property var theme: Core.ConfigService.section("theme", {})
    readonly property var config: Core.ModuleRegistry.packageConfig(moduleId)
    readonly property var privateConfig: Core.ConfigService.packagePrivateConfig(moduleId)
    readonly property var service: {
        serviceRevision;
        return Core.ModuleRegistry.serviceInstance(moduleId);
    }
    readonly property QtObject popup: PopupController {
        moduleId: root.moduleId
        screen: root.effectiveScreen
    }

    function openPopup() {
        popup.open();
    }

    function closePopup() {
        popup.close();
    }

    function togglePopup() {
        popup.toggle();
    }

    function sendIpc(action, payload) {
        if (action === "open")
            openPopup();
        else if (action === "close")
            closePopup();
        else if (action === "toggle")
            togglePopup();
    }
}
