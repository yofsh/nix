import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import QtQuick
import "../helpers" as Helpers
import "../components" as Components
import "../config" as AppConfig

PanelWindow {
    id: root
    property int barHeight: AppConfig.Config.theme.barHeight
    readonly property bool active: agent.isActive

    property string polkitState: "hidden" // "fingerprint", "password", "success"
    property bool popupVisible: false
    property bool awaitingFpResult: false
    property string fpVisual: "" // "scanning", "match", "retry", "failed"

    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 360
    implicitHeight: 200
    visible: popupVisible || fadeAnim.running
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: popupVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        windows: [root]
        active: root.popupVisible
        onCleared: root.cancel()
    }

    // --- Polkit Agent ---
    PolkitAgent {
        id: agent
        onIsActiveChanged: {
            if (isActive) {
                root.showPolkit()
                if (flow && flow.isResponseRequired)
                    root.switchToPassword()
            } else {
                root.hidePolkit()
            }
        }
    }

    Connections {
        target: agent.flow
        enabled: agent.flow !== null

        function onIsResponseRequiredChanged() {
            if (agent.flow && agent.flow.isResponseRequired)
                root.switchToPassword()
        }

        function onAuthenticationSucceeded() {
            root.showSuccess()
        }

        function onAuthenticationFailed() {
            root.showFailure()
        }
    }

    // --- D-Bus monitor for fingerprint visual feedback ---
    Process {
        id: dbusProc
        command: ["dbus-monitor", "--system", "type='signal',interface='net.reactivated.Fprint.Device'"]
        running: true
        stdout: SplitParser {
            onRead: data => root.parseFpLine(data)
        }
    }

    // --- Sound ---
    Process { id: soundProc }
    readonly property string soundBase: "/run/current-system/sw/share/sounds/ocean/stereo/"

    function playSound(file) {
        soundProc.command = ["paplay", soundBase + file]
        soundProc.startDetached()
    }

    // --- Fingerprint D-Bus parsing ---
    function parseFpLine(line) {
        if (!agent.isActive || polkitState !== "fingerprint") return

        if (line.indexOf("member=VerifyFingerSelected") !== -1) {
            fpVisual = "scanning"
            return
        }
        if (line.indexOf("member=VerifyStatus") !== -1) {
            awaitingFpResult = true
            return
        }
        if (awaitingFpResult && line.indexOf("string \"verify-") !== -1) {
            awaitingFpResult = false
            if (line.indexOf("verify-match") !== -1)
                fpVisual = "match"
            else if (line.indexOf("verify-no-match") !== -1 || line.indexOf("verify-retry-scan") !== -1) {
                fpVisual = "retry"
                fpRetryTimer.start()
            } else
                fpVisual = "failed"
        }
    }

    Timer {
        id: fpRetryTimer
        interval: 1500
        onTriggered: if (root.polkitState === "fingerprint") root.fpVisual = "scanning"
    }

    // --- State management ---
    function showPolkit() {
        polkitState = "fingerprint"
        fpVisual = ""
        popupVisible = true
        passwordField.text = ""
        pulseAnim.start()
        playSound("dialog-information.oga")
    }

    function switchToPassword() {
        polkitState = "password"
        pulseAnim.stop()
        fingerprintIcon.opacity = 1.0
        passwordField.text = ""
        passwordField.forceActiveFocus()
    }

    function showSuccess() {
        polkitState = "success"
        pulseAnim.stop()
        fingerprintIcon.opacity = 1.0
        playSound("outcome-success.oga")
        successTimer.start()
    }

    function showFailure() {
        shakeAnim.start()
        passwordField.text = ""
        passwordField.forceActiveFocus()
    }

    function hidePolkit() {
        popupVisible = false
        polkitState = "hidden"
        pulseAnim.stop()
        fingerprintIcon.opacity = 1.0
        fpVisual = ""
        awaitingFpResult = false
    }

    function cancel() {
        if (agent.flow) agent.flow.cancelAuthenticationRequest()
    }

    function submit() {
        if (agent.flow && passwordField.text.length > 0)
            agent.flow.submit(passwordField.text)
    }

    Timer {
        id: successTimer
        interval: 1000
        onTriggered: root.hidePolkit()
    }

    // --- Visual layout ---
    Item {
        anchors.fill: parent

        Item {
            id: popupContent
            anchors.fill: parent
            opacity: 0

            states: State {
                name: "visible"; when: root.popupVisible
                PropertyChanges { target: popupContent; opacity: AppConfig.Config.theme.surfaceOpacity }
            }

            transitions: Transition {
                id: fadeAnim
                NumberAnimation { property: "opacity"; duration: AppConfig.Config.theme.popupSlideDuration; easing.type: Easing.OutCubic }
            }

            Components.PopupSurface {
                anchors.fill: parent
                topBleed: 0
            }

            Column {
                id: contentCol
                anchors.centerIn: parent
                spacing: AppConfig.Config.theme.spacingDefault
                width: parent.width - 48

                // Header icon
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.polkitState === "success" ? "\udb81\udd65" : "\uf023"
                    color: root.polkitState === "success" ? Helpers.Colors.fingerprintOk : Helpers.Colors.textDefault
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeHero

                    Behavior on color { ColorAnimation { duration: 200 } }
                }

                // Polkit message
                Text {
                    width: parent.width
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: agent.flow ? agent.flow.message : ""
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    visible: root.polkitState !== "success"
                }

                // --- Fingerprint section ---
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: AppConfig.Config.theme.spacingSmall
                    visible: root.polkitState === "fingerprint"

                    Text {
                        id: fingerprintIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.fpVisual === "match" ? "\udb81\udd65" : "\ue23f"
                        color: {
                            if (root.fpVisual === "match") return Helpers.Colors.fingerprintOk
                            if (root.fpVisual === "retry" || root.fpVisual === "failed") return Helpers.Colors.fingerprintFail
                            return Helpers.Colors.textDefault
                        }
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeDisplay

                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            if (root.fpVisual === "match") return "Authenticated"
                            if (root.fpVisual === "retry") return "Try again"
                            if (root.fpVisual === "failed") return "Fingerprint failed"
                            return "Scan finger"
                        }
                        color: fingerprintIcon.color
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeIcon
                        font.bold: true
                    }
                }

                // --- Password section ---
                Column {
                    id: passwordSection
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: AppConfig.Config.theme.spacingMedium
                    visible: root.polkitState === "password"
                    width: parent.width

                    Rectangle {
                        width: parent.width
                        height: 32
                        color: Qt.rgba(1, 1, 1, 0.08)
                        radius: 8
                        border.color: passwordField.activeFocus ? Helpers.Colors.accent : Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        TextInput {
                            id: passwordField
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: Helpers.Colors.textDefault
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeMedium
                            echoMode: agent.flow && agent.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            clip: true

                            Keys.onReturnPressed: root.submit()
                            Keys.onEscapePressed: root.cancel()
                        }
                    }

                    Text {
                        width: parent.width
                        text: agent.flow && agent.flow.supplementaryMessage ? agent.flow.supplementaryMessage : ""
                        color: Helpers.Colors.fingerprintFail
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeBody
                        horizontalAlignment: Text.AlignHCenter
                        visible: text !== ""
                        wrapMode: Text.WordWrap
                    }
                }

                // --- Success text ---
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Authenticated"
                    color: Helpers.Colors.fingerprintOk
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeIcon
                    font.bold: true
                    visible: root.polkitState === "success"
                }
            }
        }
    }

    // Escape handler for non-password states
    Item {
        focus: root.popupVisible && root.polkitState !== "password"
        Keys.onEscapePressed: root.cancel()
    }

    // --- Shake animation on auth failure ---
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: contentCol; property: "anchors.horizontalCenterOffset"; to: -10; duration: 50 }
        NumberAnimation { target: contentCol; property: "anchors.horizontalCenterOffset"; to: 10; duration: 50 }
        NumberAnimation { target: contentCol; property: "anchors.horizontalCenterOffset"; to: -6; duration: 50 }
        NumberAnimation { target: contentCol; property: "anchors.horizontalCenterOffset"; to: 6; duration: 50 }
        NumberAnimation { target: contentCol; property: "anchors.horizontalCenterOffset"; to: 0; duration: 50 }
    }

    // --- Pulse animation for fingerprint scanning ---
    SequentialAnimation {
        id: pulseAnim
        loops: Animation.Infinite
        NumberAnimation { target: fingerprintIcon; property: "opacity"; from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { target: fingerprintIcon; property: "opacity"; from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
    }
}
