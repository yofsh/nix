import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "../../core" as Core

Item {
    id: root
    implicitWidth: notifText.implicitWidth
    implicitHeight: parent ? parent.height : 30

    property var context: null
    property int windowRevision: Core.ModuleRegistry.windowRevision
    readonly property var notificationsWindow: {
        windowRevision;
        var screenName = context && context.screen ? context.screen.name : "global";
        return Core.ModuleRegistry.windowInstance("notifications", screenName);
    }

    property int count: notificationsWindow ? notificationsWindow.activeCount : 0
    property bool dnd: notificationsWindow ? notificationsWindow.dnd : false

    property string displayText: {
        if (dnd) return count > 0 ? "󰂛 " + count : "󰂛";
        if (count > 0) return "󰂚 " + count;
        return "󰂚";
    }

    Components.ThemedText {
        id: notifText
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: root.dnd ? "#ff9800" : root.count > 0 ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
        font.pixelSize: AppConfig.Config.theme.fontSizeIcon
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.dnd = !root.dnd;
            if (notificationsWindow && notificationsWindow.dnd !== root.dnd)
                notificationsWindow.dnd = root.dnd;
        }
    }
}
