import QtQuick

Item {
    id: root

    property var context
    readonly property var service: context ? context.service : null
    readonly property var theme: context ? context.theme : ({})
    readonly property var config: context ? context.config : ({})

    implicitWidth: label.implicitWidth + 4
    implicitHeight: parent ? parent.height : 22

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: (root.config.label || "example") + ": " + (root.service ? root.service.value : 0)
        color: theme.colors && theme.colors.textMuted ? theme.colors.textMuted : "white"
        font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
        font.pixelSize: theme.fontSizeSmall || 10
    }
}
