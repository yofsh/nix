import QtQuick
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: notifText.implicitWidth + 12
    implicitHeight: parent ? parent.height : 30

    property int count: 0
    property bool dnd: false

    property string displayText: {
        if (dnd) return count > 0 ? "󰵙 " + count : "󰂞";
        if (count > 0) return "󰂚 " + count;
        return "󰂚";
    }

    Text {
        id: notifText
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: root.count > 0 ? Helpers.Colors.textDefault : Helpers.Colors.textMuted
        font.family: "DejaVuSansM Nerd Font"
        font.pixelSize: 14
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dnd = !root.dnd
    }
}
