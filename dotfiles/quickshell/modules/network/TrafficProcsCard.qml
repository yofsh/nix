import QtQuick
import Quickshell
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig
import "../../helpers/Format.js" as Format

// Top processes by traffic: per-app usage bars with realtime/avg speed and
// accumulated totals over the daemon's 1-minute window.
Rectangle {
    id: root

    // [name, count, rx, tx, total (bytes in window), rxr/txr (now), rxa/txa (avg)]
    property var trafficProcs: []
    // Speed shown next to the accumulated total: true = instant, false = 1-min avg.
    property bool trafficNow: true

    readonly property real trafficProcMax: {
        var m = 0;
        for (var i = 0; i < trafficProcs.length; i++) {
            var t = trafficProcs[i].total || 0;
            if (t > m) m = t;
        }
        return m > 0 ? m : 1;
    }

    height: trafficProcCol.implicitHeight + 22
    color: Qt.rgba(1, 1, 1, 0.04)
    radius: 8

    function prettyProcName(comm) {
        if (!comm) return "?";
        return ("" + comm).replace(/^\./, "").replace(/-wrappe?d?$/, "");
    }

    // Resolve an app icon from the executable name (cached per name).
    property var procIconCache: ({})
    function procIconFor(name) {
        var n = prettyProcName(name);
        if (root.procIconCache[n] !== undefined) return root.procIconCache[n];
        var src = "";
        var entry = DesktopEntries.heuristicLookup(n);
        if (entry && entry.icon) src = Quickshell.iconPath(entry.icon, true) || "";
        if (!src) src = Quickshell.iconPath(n.toLowerCase(), true) || "";
        if (!src) src = Quickshell.iconPath("application-x-executable", true) || "";
        root.procIconCache[n] = src;
        return src;
    }

    // Heat-map the realtime speed by magnitude so heavy talkers stand out.
    function rateColor(bytesPerSec) {
        if (!bytesPerSec || bytesPerSec < 1024) return Helpers.Colors.textMuted; // <1 KB/s idle
        if (bytesPerSec < 262144) return "#66bb6a";        // green   <256 KB/s
        if (bytesPerSec < 1048576) return "#42a5f5";       // blue    <1 MB/s
        if (bytesPerSec < 10485760) return "#ffa726";      // orange  <10 MB/s
        return "#ef5350";                                  // red     ≥10 MB/s
    }

    Column {
        id: trafficProcCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        anchors.topMargin: 10
        spacing: 3

        Item {
            width: trafficProcCol.width
            height: 18
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String.fromCodePoint(0xF04E1)   // 󰓡 swap-vertical
                    color: "#42a5f5"
                    font.pixelSize: 14
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Top processes by traffic"
                    font.bold: true
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "TCP · speed + total used (1 min)"
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
                // Bar legend
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 2
                    color: Qt.rgba(0.26, 0.65, 0.96, 0.8)
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "down"
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8; height: 8; radius: 2
                    color: Qt.rgba(1.0, 0.65, 0.15, 0.8)
                }
                Components.ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "up"
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
            }
            // Speed-mode toggle
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: tpChipText.implicitWidth + 16
                height: 18
                radius: 4
                color: tpChipMa.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                Components.ThemedText {
                    id: tpChipText
                    anchors.centerIn: parent
                    text: (root.trafficNow ? "now" : "1 min avg") + "  ⇄"
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }
                MouseArea {
                    id: tpChipMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.trafficNow = !root.trafficNow
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.07) }

        // Column headers, aligned over the speed / total cell pairs
        Item {
            width: trafficProcCol.width
            height: 12
            visible: root.trafficProcs.length > 0
            Components.ThemedText {
                anchors.right: parent.right
                anchors.rightMargin: 8
                width: 162
                horizontalAlignment: Text.AlignHCenter
                text: "total · 1 min"
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
            }
            Components.ThemedText {
                anchors.right: parent.right
                anchors.rightMargin: 192
                width: 184
                horizontalAlignment: Text.AlignHCenter
                text: root.trafficNow ? "realtime speed" : "avg speed · 1 min"
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
            }
        }

        Components.ThemedText {
            visible: root.trafficProcs.length === 0
            text: "No TCP traffic"
            muted: true
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
        }

        Repeater {
            model: root.trafficProcs
            delegate: Item {
                required property var modelData
                width: trafficProcCol.width
                height: 24

                // Usage bar: width = total (rx+tx) vs the busiest app,
                // split into download (blue) + upload (orange) segments.
                Rectangle {
                    id: tpBar
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height - 4
                    radius: 4
                    clip: true
                    color: "transparent"
                    width: Math.max(0, Math.min(1, (modelData.total || 0) / root.trafficProcMax)) * parent.width
                    Row {
                        anchors.fill: parent
                        Rectangle {
                            width: tpBar.width * ((modelData.total > 0) ? (modelData.rx / modelData.total) : 0)
                            height: parent.height
                            color: Qt.rgba(0.26, 0.65, 0.96, 0.33)   // download
                        }
                        Rectangle {
                            width: tpBar.width * ((modelData.total > 0) ? (modelData.tx / modelData.total) : 0)
                            height: parent.height
                            color: Qt.rgba(1.0, 0.65, 0.15, 0.33)     // upload
                        }
                    }
                }

                Image {
                    id: tpIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    sourceSize.width: 16
                    sourceSize.height: 16
                    smooth: true
                    source: root.procIconFor(modelData.name)
                    visible: source != ""
                }
                Components.ThemedText {
                    id: tpName
                    anchors.left: tpIcon.visible ? tpIcon.right : parent.left
                    anchors.leftMargin: tpIcon.visible ? 7 : 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * 0.42
                    elide: Text.ElideRight
                    text: root.prettyProcName(modelData.name)
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                Components.ThemedText {
                    visible: (modelData.count || 1) > 1
                    anchors.left: tpName.right
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×" + modelData.count
                    muted: true
                    opacity: 0.7
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeTiny
                }

                // ── accumulated total used (right column pair) ──
                Components.ThemedText {
                    id: tpUpTotal
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76
                    horizontalAlignment: Text.AlignRight
                    text: "↑ " + Format.bytes(modelData.tx || 0)
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                Components.ThemedText {
                    id: tpDownTotal
                    anchors.right: tpUpTotal.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76
                    horizontalAlignment: Text.AlignRight
                    text: "↓ " + Format.bytes(modelData.rx || 0)
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                // ── realtime speed (left column pair) ──
                Components.ThemedText {
                    id: tpUpSpeed
                    anchors.right: tpDownTotal.left
                    anchors.rightMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    width: 88
                    horizontalAlignment: Text.AlignRight
                    text: "↑ " + Format.rate(root.trafficNow ? (modelData.txr || 0) : (modelData.txa || 0))
                    color: root.rateColor(root.trafficNow ? (modelData.txr || 0) : (modelData.txa || 0))
                    font.bold: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
                Components.ThemedText {
                    anchors.right: tpUpSpeed.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 88
                    horizontalAlignment: Text.AlignRight
                    text: "↓ " + Format.rate(root.trafficNow ? (modelData.rxr || 0) : (modelData.rxa || 0))
                    color: root.rateColor(root.trafficNow ? (modelData.rxr || 0) : (modelData.rxa || 0))
                    font.bold: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                }
            }
        }
    }
}
