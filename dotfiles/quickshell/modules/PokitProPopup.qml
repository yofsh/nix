import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../helpers" as Helpers
import "../components" as Components
import "../config" as AppConfig

PanelWindow {
    id: root
    property int barHeight: AppConfig.Config.theme.barHeight
    property bool popupOpen: false
    property var service: null

    // currentTab: "measure" | "logger" | "realtime"
    property string currentTab: "measure"
    // DSO window selection (ms) — 1024 samples at mapped rate.
    property int dsoWindowMs: 1000

    Process {
        id: startPokitdProc
        command: ["systemctl", "--user", "start", "pokitd"]
    }

    anchors.top: true
    exclusionMode: ExclusionMode.Ignore
    margins.top: barHeight
    implicitWidth: 540
    implicitHeight: 360
    visible: popupOpen
    color: "transparent"

    readonly property bool errorState: service && service.state === "error"
    readonly property bool connectingState: service && (service.state === "connecting" || service.state === "reconnecting")
    readonly property bool activeState: service && service.state === "active"

    function fmtReading() {
        if (!service || service.readingTimestamp === 0) return "—";
        const v = service.readingValue;
        const abs = Math.abs(v);
        let digits = 3;
        if (abs >= 100) digits = 1;
        else if (abs >= 10) digits = 2;
        return v.toFixed(digits);
    }

    function fmtAge() {
        if (!service || service.readingTimestamp === 0) return "";
        const ms = Date.now() - service.readingTimestamp;
        if (ms < 1000) return ms + " ms ago";
        return Math.round(ms / 1000) + " s ago";
    }

    // Tab selection with leave/enter side-effects. Always runs even when
    // `next === currentTab` so that e.g. clicking Measure after STOP resumes.
    function selectTab(next) {
        if (!service) { currentTab = next; return; }
        // Leave
        if (currentTab === "measure" && next !== "measure")
            service.setPaused(true);
        if (currentTab === "logger" && next !== "logger" && service.loggerRunning)
            service.stopLogger();
        if (currentTab === "realtime" && next !== "realtime")
            service.cancelDso();
        // Enter
        if (next === "measure") service.setPaused(false);
        currentTab = next;
    }

    // When the popup is first opened onto the Measure tab, make sure we're
    // subscribed. Does not touch paused state on close — other tabs may be
    // intentionally running in the background (e.g. logger).
    onPopupOpenChanged: {
        if (popupOpen && service && currentTab === "measure" && service.paused)
            service.setPaused(false);
    }

    Timer {
        running: root.popupOpen && (root.activeState || (root.service && root.service.dsoCapturing))
        interval: 250
        repeat: true
        onTriggered: ageRefresh.value = Date.now()
    }
    QtObject { id: ageRefresh; property double value: 0 }

    Item {
        anchors.fill: parent

        Item {
            id: popupContent
            width: parent.width
            height: parent.height
            opacity: AppConfig.Config.theme.surfaceOpacityStrong

            Components.PopupSurface {
                anchors.fill: parent
            }

            // Top status strip
            Row {
                id: topStrip
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                anchors.topMargin: 8
                spacing: AppConfig.Config.theme.spacingMedium

                Text {
                    text: "\udb82\udd29"
                    color: root.errorState ? Helpers.Colors.multimeterError
                         : root.activeState ? Helpers.Colors.multimeterActive
                         : root.connectingState ? Helpers.Colors.multimeter
                         : Helpers.Colors.multimeterIdle
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeIconLarge
                }
                Text {
                    text: root.service ? (root.service.deviceName || "Pokit") : "Pokit"
                    color: Helpers.Colors.textDefault
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeBody
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: {
                        if (!root.service) return "";
                        const s = root.service.state;
                        if (s === "absent") return "no device";
                        if (s === "discovered") return "discovered";
                        if (s === "connecting") return "connecting…";
                        if (s === "reconnecting") return "reconnecting…";
                        if (s === "active") return "live";
                        if (s === "error") return "error";
                        return s;
                    }
                    color: root.errorState ? Helpers.Colors.multimeterError
                         : root.activeState ? Helpers.Colors.multimeterActive
                         : Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 12; height: 1 }
                Text {
                    text: root.service && root.service.batteryLevel >= 0
                          ? root.service.batteryLevel + "%  battery" : ""
                    visible: root.service && root.service.batteryLevel >= 0
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.service && root.service.firmware
                          ? "fw " + root.service.firmware : ""
                    visible: root.service && root.service.firmware
                    color: Helpers.Colors.textMuted
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: 6; height: 1 }
                Text {
                    text: root.service && root.service.paused ? "⏸ paused" : ""
                    visible: root.service && root.service.paused
                    color: Helpers.Colors.multimeter
                    font.family: AppConfig.Config.theme.fontFamily
                    font.pixelSize: AppConfig.Config.theme.fontSizeXSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Tab bar
            Item {
                id: tabBar
                anchors.top: topStrip.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                height: 30

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: AppConfig.Config.theme.spacingSmall
                    Repeater {
                        model: [
                            { key: "measure",  label: "Measure" },
                            { key: "logger",   label: "Logger" },
                            { key: "realtime", label: "Realtime" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: 100; height: 30
                            radius: AppConfig.Config.theme.cardRadiusSmall
                            readonly property bool isActive: root.currentTab === modelData.key
                            color: isActive
                                   ? Qt.rgba(0.65, 0.89, 0.63, 0.20)
                                   : Qt.rgba(1, 1, 1, 0.04)
                            border.color: isActive
                                          ? Helpers.Colors.multimeterActive
                                          : Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: parent.isActive
                                       ? Helpers.Colors.multimeterActive
                                       : Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeBody
                                font.bold: parent.isActive
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectTab(modelData.key)
                            }
                        }
                    }
                }

                Rectangle {
                    id: stopBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 86; height: 30
                    radius: AppConfig.Config.theme.cardRadiusSmall
                    readonly property bool stopActive: root.service
                        && (!root.service.paused
                            || root.service.loggerRunning
                            || root.service.dsoCapturing)
                    color: stopActive
                           ? Qt.rgba(0.95, 0.55, 0.66, 0.18)
                           : Qt.rgba(1, 1, 1, 0.04)
                    border.color: stopActive
                                  ? Helpers.Colors.multimeterError
                                  : Qt.rgba(1, 1, 1, 0.10)
                    border.width: 1
                    opacity: stopActive ? 1.0 : 0.45
                    Text {
                        anchors.centerIn: parent
                        text: "■ STOP"
                        color: parent.stopActive
                               ? Helpers.Colors.multimeterError
                               : Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeBody
                        font.bold: parent.stopActive
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: parent.stopActive ? Qt.PointingHandCursor : Qt.ArrowCursor
                        enabled: parent.stopActive
                        onClicked: if (root.service) root.service.panicStop()
                    }
                }

                Rectangle {
                    id: linkBtn
                    anchors.right: stopBtn.left
                    anchors.rightMargin: AppConfig.Config.theme.spacingSmall
                    anchors.verticalCenter: parent.verticalCenter
                    width: 110; height: 30
                    radius: AppConfig.Config.theme.cardRadiusSmall
                    // "connected" means BLE link is up (ready or in-flight)
                    readonly property bool connected: root.service
                        && (root.activeState || root.connectingState)
                    color: connected
                           ? Qt.rgba(1, 1, 1, 0.04)
                           : Qt.rgba(0.65, 0.89, 0.63, 0.14)
                    border.color: connected
                                  ? Qt.rgba(1, 1, 1, 0.15)
                                  : Helpers.Colors.multimeterActive
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: parent.connected ? "⏻  Disconnect" : "⏻  Connect"
                        color: parent.connected
                               ? Helpers.Colors.textDefault
                               : Helpers.Colors.multimeterActive
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        font.bold: !parent.connected
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.service) return;
                            if (parent.connected) {
                                root.service.panicStop();
                                root.service.disconnect();
                            } else {
                                root.service.connect();
                                // Re-run current tab's enter action so if we're
                                // on Measure, subscription resumes once linked.
                                root.selectTab(root.currentTab);
                            }
                        }
                    }
                }
            }

            // Common content region (shared by all three tabs + overlays)
            Item {
                id: contentArea
                anchors.top: tabBar.bottom
                anchors.topMargin: 10
                anchors.bottom: footer.top
                anchors.bottomMargin: 6
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12

                // ─── MEASURE TAB ──────────────────────────────────────────
                Item {
                    id: measureTab
                    anchors.fill: parent
                    visible: root.currentTab === "measure" && !root.errorState

                    // Top row: big reading (left) + rolling trend chart (right)
                    Item {
                        id: readingArea
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 126

                        Item {
                            id: readingBlock
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            width: 180

                            Text {
                                id: readingText
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.verticalCenterOffset: -8
                                text: root.fmtReading()
                                color: root.activeState
                                       ? Helpers.Colors.multimeterActive
                                       : Helpers.Colors.multimeterIdle
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeDisplay
                                font.bold: true
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }
                            Text {
                                anchors.left: readingText.right
                                anchors.bottom: readingText.bottom
                                anchors.bottomMargin: 6
                                anchors.leftMargin: 4
                                text: root.service ? root.service.readingUnit : ""
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeIconLarge
                            }
                            Text {
                                anchors.top: readingText.bottom
                                anchors.horizontalCenter: readingText.horizontalCenter
                                anchors.topMargin: 6
                                text: {
                                    if (!root.service) return "";
                                    const parts = [];
                                    if (root.service.readingMode) parts.push(root.service.readingMode);
                                    if (root.service.readingRange) parts.push(root.service.readingRange);
                                    const age = root.fmtAge();
                                    if (age) { ageRefresh.value; parts.push(age); }
                                    return parts.join("  ·  ");
                                }
                                color: Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeXSmall
                                horizontalAlignment: Text.AlignHCenter
                                width: parent.width
                            }
                        }

                        Components.PokitChart {
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            anchors.left: readingBlock.right
                            anchors.leftMargin: 6
                            anchors.right: parent.right
                            yUnit: root.service ? root.service.readingUnit : ""
                            traceColor: Helpers.Colors.multimeterActive
                            caption: "last 60 s"
                            emptyText: root.service && root.service.paused
                                       ? "paused — resume to see a live trend"
                                       : "waiting for readings…"
                            points: {
                                if (!root.service
                                    || !root.service.readingHistory
                                    || root.service.readingHistory.length === 0)
                                    return [];
                                const hist = root.service.readingHistory;
                                const tN = hist[hist.length - 1].t;
                                const arr = new Array(hist.length);
                                for (let i = 0; i < hist.length; ++i) {
                                    arr[i] = { x: (hist[i].t - tN) / 1000, y: hist[i].v };
                                }
                                return arr;
                            }
                        }
                    }

                    // Mode + Range controls
                    Components.PokitControls {
                        id: controls
                        anchors.top: readingArea.bottom
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        anchors.right: parent.right
                        service: root.service
                    }

                    // Torch + Flash small utilities
                    Row {
                        anchors.top: controls.bottom
                        anchors.topMargin: 8
                        anchors.left: parent.left
                        spacing: AppConfig.Config.theme.spacingSmall

                        Rectangle {
                            width: 90; height: 30
                            radius: AppConfig.Config.theme.cardRadiusSmall
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                anchors.centerIn: parent
                                text: "\udb80\udcc8  Torch"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            }
                            MouseArea {
                                id: torchArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                property bool torchOn: false
                                onClicked: {
                                    torchOn = !torchOn;
                                    if (root.service) root.service.setTorch(torchOn);
                                }
                            }
                        }

                        Rectangle {
                            width: 90; height: 30
                            radius: AppConfig.Config.theme.cardRadiusSmall
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                anchors.centerIn: parent
                                text: "\udb83\udd97  Flash LED"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.service) root.service.flashLed()
                            }
                        }
                    }
                }

                // ─── LOGGER TAB ───────────────────────────────────────────
                Item {
                    id: loggerTab
                    anchors.fill: parent
                    visible: root.currentTab === "logger" && !root.errorState

                    Text {
                        id: loggerStatus
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        text: {
                            if (!root.service) return "";
                            const n = root.service.loggerSamples ? root.service.loggerSamples.length : 0;
                            const interval = root.service._loggerMetaIntervalMs || 1000;
                            if (root.service.loggerRunning)
                                return "Running  ·  " + n + " samples @ " + interval + " ms";
                            if (n > 0)
                                return "Stopped  ·  " + n + " samples fetched";
                            return "Stopped  ·  no samples — press Start, then Fetch";
                        }
                        color: root.service && root.service.loggerRunning
                               ? Helpers.Colors.multimeterActive
                               : Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                    }

                    Row {
                        id: loggerActions
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        spacing: AppConfig.Config.theme.spacingSmall

                        Rectangle {
                            width: 80; height: 30
                            radius: AppConfig.Config.theme.cardRadiusSmall
                            readonly property bool canStart: root.service && !root.service.loggerRunning
                            color: canStart ? Qt.rgba(0.65, 0.89, 0.63, 0.18) : Qt.rgba(1, 1, 1, 0.04)
                            border.color: canStart ? Helpers.Colors.multimeterActive : Qt.rgba(1, 1, 1, 0.10)
                            opacity: canStart ? 1 : 0.5
                            Text {
                                anchors.centerIn: parent
                                text: "▶  Start"
                                color: parent.canStart ? Helpers.Colors.multimeterActive : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: parent.canStart
                                onClicked: if (root.service) root.service.startLogger()
                            }
                        }

                        Rectangle {
                            width: 80; height: 30
                            radius: AppConfig.Config.theme.cardRadiusSmall
                            readonly property bool canStop: root.service && root.service.loggerRunning
                            color: canStop ? Qt.rgba(0.95, 0.55, 0.66, 0.15) : Qt.rgba(1, 1, 1, 0.04)
                            border.color: canStop ? Helpers.Colors.multimeterError : Qt.rgba(1, 1, 1, 0.10)
                            opacity: canStop ? 1 : 0.5
                            Text {
                                anchors.centerIn: parent
                                text: "■  Stop"
                                color: parent.canStop ? Helpers.Colors.multimeterError : Helpers.Colors.textMuted
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                enabled: parent.canStop
                                onClicked: if (root.service) root.service.stopLogger()
                            }
                        }

                        Rectangle {
                            width: 80; height: 30
                            radius: AppConfig.Config.theme.cardRadiusSmall
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                anchors.centerIn: parent
                                text: "\udb80\udf90  Fetch"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.service) root.service.fetchLogger()
                            }
                        }

                        Rectangle {
                            width: 80; height: 30
                            radius: AppConfig.Config.theme.cardRadiusSmall
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.10)
                            Text {
                                anchors.centerIn: parent
                                text: "Clear"
                                color: Helpers.Colors.textDefault
                                font.family: AppConfig.Config.theme.fontFamily
                                font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (root.service) root.service.loggerSamples = []
                            }
                        }
                    }

                    // History graph
                    Components.PokitChart {
                        anchors.top: loggerStatus.bottom
                        anchors.topMargin: 6
                        anchors.bottom: loggerActions.top
                        anchors.bottomMargin: 6
                        anchors.left: parent.left
                        anchors.right: parent.right
                        yUnit: root.service ? root.service._loggerMetaUnit : ""
                        traceColor: Helpers.Colors.multimeter
                        emptyText: "No samples — press Start, then Fetch"
                        caption: {
                            if (!root.service) return "";
                            const n = root.service.loggerSamples
                                      ? root.service.loggerSamples.length : 0;
                            if (n === 0) return "";
                            const iv = root.service._loggerMetaIntervalMs || 1000;
                            return n + " samples · " + iv + " ms interval";
                        }
                        points: {
                            if (!root.service
                                || !root.service.loggerSamples
                                || root.service.loggerSamples.length === 0)
                                return [];
                            const s = root.service.loggerSamples;
                            const t0 = s[0].timestamp;
                            const arr = new Array(s.length);
                            for (let i = 0; i < s.length; ++i) {
                                arr[i] = { x: (s[i].timestamp - t0) / 1000, y: s[i].value };
                            }
                            return arr;
                        }
                    }
                }

                // ─── REALTIME (DSO) TAB ───────────────────────────────────
                Item {
                    id: realtimeTab
                    anchors.fill: parent
                    visible: root.currentTab === "realtime" && !root.errorState

                    Row {
                        id: windowPicker
                        anchors.top: parent.top
                        anchors.left: parent.left
                        spacing: AppConfig.Config.theme.spacingSmall
                        Repeater {
                            model: [
                                { ms: 100,   label: "100 ms" },
                                { ms: 500,   label: "500 ms" },
                                { ms: 1000,  label: "1 s" },
                                { ms: 5000,  label: "5 s" },
                                { ms: 10000, label: "10 s" }
                            ]
                            Rectangle {
                                required property var modelData
                                width: 64; height: 28
                                radius: AppConfig.Config.theme.cardRadiusSmall
                                readonly property bool isActive: root.dsoWindowMs === modelData.ms
                                color: isActive
                                       ? Qt.rgba(0.97, 0.89, 0.69, 0.18)
                                       : Qt.rgba(1, 1, 1, 0.04)
                                border.color: isActive
                                              ? Helpers.Colors.multimeter
                                              : Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.isActive
                                           ? Helpers.Colors.multimeter
                                           : Helpers.Colors.textMuted
                                    font.family: AppConfig.Config.theme.fontFamily
                                    font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                                    font.bold: parent.isActive
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.dsoWindowMs = modelData.ms
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: captureBtn
                        anchors.top: parent.top
                        anchors.right: parent.right
                        width: 96; height: 28
                        radius: AppConfig.Config.theme.cardRadiusSmall
                        readonly property bool capturing: root.service && root.service.dsoCapturing
                        color: capturing
                               ? Qt.rgba(0.97, 0.89, 0.69, 0.22)
                               : Qt.rgba(0.65, 0.89, 0.63, 0.18)
                        border.color: capturing
                                      ? Helpers.Colors.multimeter
                                      : Helpers.Colors.multimeterActive
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: parent.capturing ? "● capturing…" : "● Capture"
                            color: parent.capturing
                                   ? Helpers.Colors.multimeter
                                   : Helpers.Colors.multimeterActive
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: !parent.capturing
                            onClicked: if (root.service)
                                root.service.captureDsoByWindow(
                                    root.service.currentMode, root.dsoWindowMs)
                        }
                    }

                    Components.PokitChart {
                        id: dsoChart
                        anchors.top: windowPicker.bottom
                        anchors.topMargin: 8
                        anchors.bottom: dsoCaption.top
                        anchors.bottomMargin: 4
                        anchors.left: parent.left
                        anchors.right: parent.right
                        yUnit: root.service ? root.service.dsoUnit : ""
                        traceColor: Helpers.Colors.multimeterActive
                        emptyText: root.service && root.service.dsoCapturing
                                   ? "capturing… " + root.service.dsoProgress + " / " + root.service.dsoExpected
                                   : "Pick a window and press Capture — current mode: " +
                                     (root.service ? root.service.currentMode : "")
                        caption: {
                            if (!root.service) return "";
                            const n = root.service.dsoTrace ? root.service.dsoTrace.length : 0;
                            if (n === 0) return "";
                            const r = root.service.dsoSampleRateHz || 0;
                            return n + " samples @ " + r + " Hz · " + root.service.dsoMode;
                        }
                        points: {
                            if (!root.service) return [];
                            const t = root.service.dsoTrace;
                            const r = root.service.dsoSampleRateHz;
                            if (!t || t.length === 0 || !r || r <= 0) return [];
                            const arr = new Array(t.length);
                            for (let i = 0; i < t.length; ++i) {
                                arr[i] = { x: i / r, y: t[i] };
                            }
                            return arr;
                        }
                    }

                    Text {
                        id: dsoCaption
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.service && root.service.dsoCapturing
                              ? "capturing…  " + root.service.dsoProgress + " / " + root.service.dsoExpected
                              : ""
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeXSmall
                    }
                }
            }

            // Footer: MAC + activity + lastError
            Text {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 8
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (!root.service) return "";
                    ageRefresh.value;  // tick
                    const parts = [];
                    if (root.service.deviceMac) parts.push(root.service.deviceMac);
                    let a = root.service.activity || "idle";
                    if (root.service.activityStartedAt > 0) {
                        const ms = Date.now() - root.service.activityStartedAt;
                        a += " · " + (ms / 1000).toFixed(1) + "s";
                    }
                    parts.push(a);
                    if (root.service.lastError && root.errorState)
                        parts.push(root.service.lastError);
                    return parts.join("   ·   ");
                }
                color: Helpers.Colors.textMuted
                font.family: AppConfig.Config.theme.fontFamily
                font.pixelSize: AppConfig.Config.theme.fontSizeXSmall
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            // Daemon-offline overlay — takes priority over error
            Item {
                anchors.top: topStrip.bottom
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                visible: root.service && !root.service.daemonConnected

                Column {
                    anchors.centerIn: parent
                    spacing: AppConfig.Config.theme.spacingDefault

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\udb81\udd5a"
                        color: Helpers.Colors.multimeter
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeHero
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "pokitd is not running"
                        color: Helpers.Colors.multimeter
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeMedium
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "The BLE daemon at " +
                              (root.service ? root.service.socketPath : "") +
                              " is offline."
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        width: 400
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 160; height: 30
                        radius: AppConfig.Config.theme.cardRadiusSmall
                        color: Qt.rgba(0.97, 0.89, 0.69, 0.18)
                        border.color: Helpers.Colors.multimeter
                        Text {
                            anchors.centerIn: parent
                            text: "Start pokitd"
                            color: Helpers.Colors.multimeter
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeBody
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: startPokitdProc.running = true
                        }
                    }
                }
            }

            // Error overlay
            Item {
                anchors.top: topStrip.bottom
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 16
                visible: root.errorState && root.service && root.service.daemonConnected

                Column {
                    anchors.centerIn: parent
                    spacing: AppConfig.Config.theme.spacingDefault

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "\udb81\udd5a"
                        color: Helpers.Colors.multimeterError
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeHero
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Connection error"
                        color: Helpers.Colors.multimeterError
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeMedium
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.service ? (root.service.lastError || "unknown error") : ""
                        color: Helpers.Colors.textMuted
                        font.family: AppConfig.Config.theme.fontFamily
                        font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        width: 380
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 100; height: 28
                        radius: AppConfig.Config.theme.cardRadiusSmall
                        color: Qt.rgba(0.95, 0.55, 0.66, 0.15)
                        border.color: Helpers.Colors.multimeterError
                        Text {
                            anchors.centerIn: parent
                            text: "Retry now"
                            color: Helpers.Colors.multimeterError
                            font.family: AppConfig.Config.theme.fontFamily
                            font.pixelSize: AppConfig.Config.theme.fontSizeSmall
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.service) root.service.retry()
                        }
                    }
                }
            }
        }
    }
}
