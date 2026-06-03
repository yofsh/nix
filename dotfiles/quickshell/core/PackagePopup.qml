import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import "." as Core
import "../helpers" as Helpers
import "../config" as AppConfig

// Reusable popup window. Owns everything every popup used to repeat: placement
// under the bar, open/close state (synced with the driving widget + PopupService),
// click-outside-to-close, and `qs ipc call <id> open|close|toggle`. The module's
// Popup.qml is just a content Item passed as the child — no window boilerplate,
// no IPC, no open/close logic per module.
//
//   Core.PackagePopup { moduleId: "battery"; screen: hostScreenInfo; barWindow: barWindow
//       M_battery.Popup {}
//   }
PanelWindow {
    id: root

    required property string moduleId
    property var screen: null
    property var barWindow: null
    // Provide the standard open/close/toggle IPC. Set false for modules whose
    // Service.qml defines its own IpcHandler for this target (e.g. network).
    property bool ipc: true
    // Set true for popups that take keyboard input (e.g. focus's label field).
    property bool keyboardFocus: false

    // The module's popup body (a plain Item), parked in `holder`.
    default property alias content: holder.data
    property Item body: null

    readonly property string screenName: screen && screen.name ? screen.name : "global"
    readonly property var context: ModuleContext {
        moduleId: root.moduleId
        screen: root.screen
    }
    readonly property int barHeight: AppConfig.Config.theme.barHeight || 22

    // Open state: a widget may drive it via its own `popupOpen`, else PopupService.
    property int widgetRevision: Core.ModuleRegistry.widgetRevision
    readonly property var widget: {
        widgetRevision;
        return Core.ModuleRegistry.widgetInstance(moduleId, screenName);
    }
    readonly property bool widgetDrives: widget && "popupOpen" in widget

    property int popupRevision: Core.PopupService.revision
    readonly property bool popupOpen: {
        popupRevision;
        widgetRevision;
        return widgetDrives ? !!widget.popupOpen : Core.PopupService.isOpen(moduleId, screenName);
    }

    // Placement (was copy-pasted into every popup).
    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight + (AppConfig.Config.theme.popupTopGap || 0)
    color: "transparent"
    visible: popupOpen
    implicitWidth: body ? (body.implicitWidth || 1) : 1
    implicitHeight: body ? (body.implicitHeight || 1) : 1

    WlrLayershell.keyboardFocus: (keyboardFocus && popupOpen) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    function close() {
        if (widgetDrives)
            widget.popupOpen = false;
        Core.PopupService.close(moduleId, screenName);
    }

    Item {
        id: holder
        anchors.fill: parent
    }

    Component.onCompleted: {
        body = holder.children.length > 0 ? holder.children[0] : null;
        if (!body)
            return;
        if ("context" in body)
            body.context = root.context;
        if (Helpers.ModuleConfig.has(moduleId) && "config" in body)
            body.config = Qt.binding(function() { return root.context.config; });
        if ("screen" in body)
            body.screen = root.screen;
        if ("barHeight" in body)
            body.barHeight = Qt.binding(function() { return root.barHeight; });
        if ("popupOpen" in body)
            body.popupOpen = Qt.binding(function() { return root.popupOpen; });
    }

    HyprlandFocusGrab {
        windows: root.barWindow ? [root.barWindow, root] : [root]
        active: root.popupOpen
        onCleared: root.close()
    }

    Loader {
        active: root.ipc
        sourceComponent: IpcHandler {
            target: root.moduleId
            function toggle() { root.context.togglePopup(); }
            function open() { root.context.openPopup(); }
            function close() { root.context.closePopup(); }
        }
    }
}
