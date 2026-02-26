import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../helpers" as Helpers

PanelWindow {
    id: root
    property int barHeight: 22

    // States: "hidden", "prompt", "success", "failure", "timeout"
    property string fpState: "hidden"
    property bool popupVisible: false

    // D-Bus line parsing state
    property bool awaitingResult: false

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: 240
    implicitHeight: 110
    visible: popupVisible || slideAnim.running
    color: "transparent"

    // --- D-Bus monitor process ---
    Process {
        id: dbusProc
        command: ["dbus-monitor", "--system", "type='signal',interface='net.reactivated.Fprint.Device'"]
        running: true
        stdout: SplitParser {
            onRead: data => root.parseLine(data)
        }
    }

    // --- Hyprlock check ---
    Process {
        id: hyprlockCheck
        command: ["pgrep", "-x", "hyprlock"]
        property bool hyprlockRunning: false
        onExited: (code, status) => { hyprlockRunning = (code === 0) }
    }

    function parseLine(line) {
        if (line.indexOf("member=VerifyFingerSelected") !== -1) {
            hyprlockCheck.startDetached()
            // Small delay to let pgrep finish before we check
            promptDelayTimer.start()
            return
        }
        if (line.indexOf("member=VerifyStatus") !== -1) {
            awaitingResult = true
            return
        }
        if (awaitingResult && line.indexOf("string \"verify-") !== -1) {
            awaitingResult = false
            hyprlockCheck.startDetached()
            resultLine = line
            resultDelayTimer.start()
        }
    }

    property string resultLine: ""

    // Small delay to let pgrep finish
    Timer {
        id: promptDelayTimer
        interval: 50
        onTriggered: {
            if (hyprlockCheck.hyprlockRunning) return
            root.showState("prompt")
        }
    }

    Timer {
        id: resultDelayTimer
        interval: 50
        onTriggered: {
            if (hyprlockCheck.hyprlockRunning) return
            var line = root.resultLine
            if (line.indexOf("verify-match") !== -1) {
                root.showState("success")
            } else if (line.indexOf("verify-disconnected") !== -1 || line.indexOf("verify-unknown-error") !== -1) {
                root.showState("timeout")
            } else {
                // verify-no-match, verify-retry-scan, verify-swipe-too-short, etc.
                root.showState("failure")
            }
        }
    }

    function showState(state) {
        fpState = state
        popupVisible = true
        hideTimer.stop()
        pulseAnim.stop()

        if (state === "prompt") {
            hideTimer.interval = 30000
            hideTimer.start()
            pulseAnim.start()
        } else if (state === "success") {
            hideTimer.interval = 2000
            hideTimer.start()
        } else if (state === "failure") {
            hideTimer.interval = 3000
            hideTimer.start()
        } else if (state === "timeout") {
            hideTimer.interval = 3000
            hideTimer.start()
        }
    }

    Timer {
        id: hideTimer
        onTriggered: {
            root.popupVisible = false
            pulseAnim.stop()
            iconText.opacity = 1.0
        }
    }

    // --- Visual properties derived from state ---
    property string displayIcon: {
        if (fpState === "success") return "\udb81\udd65" // success
        return "\ue23f" // fingerprint
    }

    property color displayColor: {
        if (fpState === "success") return Helpers.Colors.fingerprintOk
        if (fpState === "failure" || fpState === "timeout") return Helpers.Colors.fingerprintFail
        return Helpers.Colors.textDefault
    }

    property string displayText: {
        if (fpState === "prompt") return "Scan finger"
        if (fpState === "success") return "Access granted"
        if (fpState === "failure") return "Declined"
        if (fpState === "timeout") return "Use password"
        return ""
    }

    // --- Slide in/out animation ---
    Item {
        anchors.fill: parent
        clip: true

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            y: -parent.height
            opacity: 0.8

            states: State {
                name: "visible"; when: root.popupVisible
                PropertyChanges { target: popupContent; y: 0 }
            }

            transitions: Transition {
                id: slideAnim
                NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.OutCubic }
            }

            Item {
                anchors.fill: parent
                clip: true

                Rectangle {
                    anchors.fill: parent
                    anchors.topMargin: -16
                    color: "#11000000"
                    radius: 16
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    id: iconText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.displayIcon
                    color: root.displayColor
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 48

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.displayText
                    color: root.displayColor
                    font.family: "DejaVuSansM Nerd Font"
                    font.pixelSize: 24
                    font.bold: true

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }
            }
        }
    }

    // --- Pulse animation for prompt state ---
    SequentialAnimation {
        id: pulseAnim
        loops: Animation.Infinite
        NumberAnimation { target: iconText; property: "opacity"; from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutSine }
        NumberAnimation { target: iconText; property: "opacity"; from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutSine }
    }
}
