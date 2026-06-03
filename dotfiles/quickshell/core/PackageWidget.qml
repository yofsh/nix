import QtQuick
import "." as Core
import "../helpers" as Helpers

// Wraps a bar module widget that is passed as a declared child (not loaded from
// a URL). Provides the hover background, interactivity/cursor, context/config/
// screen wiring, and instance registration. Because the widget lives directly in
// the object tree, Quickshell's reloader matches it across reloads, so editing a
// module reloads it in place instead of rebuilding it from scratch.
//
// Usage:
//   import "../modules/clock" as M_clock
//   Core.PackageWidget { moduleId: "clock"; screen: hostScreenInfo; M_clock.Widget {} }
Item {
    id: root

    required property string moduleId
    property var screen: null

    // The module widget is the single declared child, parked in `holder`.
    default property alias content: holder.data
    property Item widget: null

    readonly property var theme: Core.ConfigService.section("theme", {})

    readonly property var context: Core.ModuleContext {
        moduleId: root.moduleId
        screen: root.screen
    }

    // Interactive (hover highlight + pointer cursor) if the widget exposes
    // `interactive`, or drives a popup via its own `popupOpen` property.
    readonly property bool interactive: !widget
        ? false
        : ("interactive" in widget ? !!widget.interactive : ("popupOpen" in widget))
    readonly property bool hoverActive: interactive && hover.hovered && width > 0 && height > 0

    implicitWidth: widget ? (widget.implicitWidth || 0) : 0
    implicitHeight: parent ? parent.height : (widget ? (widget.implicitHeight || 0) : 0)
    width: implicitWidth
    height: implicitHeight

    function screenName() {
        return screen && screen.name ? screen.name : "global";
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

    Item {
        id: holder
        anchors.fill: parent
    }

    HoverHandler {
        id: hover
        enabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    Component.onCompleted: {
        widget = holder.children.length > 0 ? holder.children[0] : null;
        if (!widget)
            return;
        if ("context" in widget)
            widget.context = root.context;
        if (Helpers.ModuleConfig.has(moduleId) && "config" in widget)
            widget.config = Qt.binding(function() { return root.context.config; });
        if ("screen" in widget)
            widget.screen = root.screen;
        Core.ModuleRegistry.registerWidgetInstance(moduleId, screenName(), widget);
    }

    Component.onDestruction: Core.ModuleRegistry.unregisterWidgetInstance(moduleId, screenName())
}
