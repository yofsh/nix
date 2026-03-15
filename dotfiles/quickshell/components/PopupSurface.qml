import QtQuick
import "../config" as AppConfig

Item {
    id: root

    property int topBleed: AppConfig.Config.theme.surfaceTopBleed
    property color surfaceColor: AppConfig.Config.theme.surfaceColor
    property int surfaceRadius: AppConfig.Config.theme.surfaceRadius

    clip: true

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -root.topBleed
        color: root.surfaceColor
        radius: root.surfaceRadius
    }
}
