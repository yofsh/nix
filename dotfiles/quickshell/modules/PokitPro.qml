import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig
import "../state" as AppState

Item {
    id: root
    property var service: null

    readonly property bool present: service && service.state !== "absent"
    readonly property bool active: service && service.state === "active"
    readonly property bool errorState: service && service.state === "error"
    readonly property bool connecting: service && (service.state === "connecting" || service.state === "reconnecting")
    readonly property bool paused: service && service.paused

    visible: present || paused
    implicitWidth: visible ? contentRow.implicitWidth + 4 : 0
    implicitHeight: parent ? parent.height : 22

    Row {
        id: contentRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        height: parent.height

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.paused ? "⏸" : "\udb82\udd29"  // pause glyph when paused, multimeter otherwise
            color: root.paused ? Helpers.Colors.multimeter
                 : root.errorState ? Helpers.Colors.multimeterError
                 : root.active ? Helpers.Colors.multimeterActive
                 : root.connecting ? Helpers.Colors.multimeter
                 : Helpers.Colors.multimeterIdle
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeIcon

            SequentialAnimation on opacity {
                running: root.connecting
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.4; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        // Show "⏵ Pokit" label when paused to explicitly show the widget is available
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.paused
            text: "Pokit"
            color: Helpers.Colors.multimeter
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeXSmall
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.active && root.service && root.service.readingTimestamp > 0
            text: {
                if (!root.service) return "";
                const v = root.service.readingValue;
                const abs = Math.abs(v);
                let d = 2;
                if (abs >= 100) d = 0;
                else if (abs >= 10) d = 1;
                return v.toFixed(d) + (root.service.readingUnit || "");
            }
            color: Helpers.Colors.multimeterActive
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeBody
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.service && root.service.batteryLevel >= 0 && root.service.batteryLevel <= 30
            text: root.service ? root.service.batteryLevel + "%" : ""
            color: root.service && root.service.batteryLevel <= 15
                   ? Helpers.Colors.batteryCritical : Helpers.Colors.batteryWarning
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeXSmall
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
            AppState.ShellState.pokitPopupPinned = !AppState.ShellState.pokitPopupPinned;
            if (AppState.ShellState.pokitPopupPinned)
                AppState.ShellState.pokitPopupDismissed = false;
        }
    }
}
