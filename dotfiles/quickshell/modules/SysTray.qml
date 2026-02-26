import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../helpers" as Helpers

Item {
    id: root
    implicitWidth: trayRow.implicitWidth
    implicitHeight: parent ? parent.height : 30

    Row {
        id: trayRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Repeater {
            model: SystemTray.items

            Item {
                required property var modelData
                width: 14
                height: 14

                Image {
                    anchors.fill: parent
                    source: modelData.icon
                    sourceSize.width: 14
                    sourceSize.height: 14
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.LeftButton) {
                            modelData.activate();
                        } else if (mouse.button === Qt.MiddleButton) {
                            modelData.secondaryActivate();
                        } else if (mouse.button === Qt.RightButton) {
                            modelData.activate();
                        }
                    }
                }
            }
        }
    }
}
