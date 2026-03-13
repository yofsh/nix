import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../helpers" as Helpers

PanelWindow {
    id: root
    property int barHeight: 22
    property bool popupOpen: false

    anchors.top: true
    anchors.bottom: true
    exclusionMode: ExclusionMode.Ignore
    property real screenRatio: screen ? screen.width / screen.height : 16/9
    property real cardHeight: screen ? Math.floor((screen.height - 30 - 28 * 8) / 7) : 100
    property real cardWidth: cardHeight * screenRatio
    implicitWidth: cardWidth * 1.3 + 40
    visible: popupOpen
    color: "transparent"

    WlrLayershell.namespace: "quickshell-wallpaper"
    WlrLayershell.keyboardFocus: popupOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    signal closed()

    property var wallpapers: []
    property string currentWallpaper: ""
    property string originalWallpaper: ""
    property int selectedIndex: -1

    onPopupOpenChanged: {
        if (popupOpen) {
            scanProc.running = true;
            currentProc.running = true;
        } else {
            selectedIndex = -1;
        }
    }

    function previewWallpaper(path) {
        previewProc.wallpaperPath = path;
        previewProc.running = true;
    }

    function commitSelection() {
        if (selectedIndex < 0 || selectedIndex >= wallpapers.length) return;
        var path = wallpapers[selectedIndex].path;
        currentWallpaper = path;
        originalWallpaper = path;
        applyProc.wallpaperPath = path;
        applyProc.running = true;
        closed();
    }

    function revertAndClose() {
        if (originalWallpaper && originalWallpaper !== currentWallpaper) {
            previewWallpaper(originalWallpaper);
            currentWallpaper = originalWallpaper;
        }
        closed();
    }

    function moveSelection(delta) {
        if (wallpapers.length === 0) return;
        if (selectedIndex < 0) {
            for (var i = 0; i < wallpapers.length; i++) {
                if (wallpapers[i].path === currentWallpaper) {
                    selectedIndex = i;
                    return;
                }
            }
            selectedIndex = 0;
        } else {
            selectedIndex = Math.max(0, Math.min(wallpapers.length - 1, selectedIndex + delta));
        }
        var path = wallpapers[selectedIndex].path;
        currentWallpaper = path;
        previewWallpaper(path);
    }

    Process {
        id: scanProc
        command: ["bash", "-c", "find ~/pics/wallpapers -type f \\( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \\) -printf '%T@\\t%p\\n'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n");
                var items = [];
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("\t");
                    if (parts.length < 2) continue;
                    items.push({mtime: parseFloat(parts[0]), path: parts[1]});
                }
                items.sort(function(a, b) { return b.mtime - a.mtime; });
                root.wallpapers = items;
                scrollTimer.restart();
            }
        }
    }

    Process {
        id: currentProc
        command: ["bash", "-c", "readlink -f ~/.current-wallpaper"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var wp = this.text.trim();
                root.currentWallpaper = wp;
                root.originalWallpaper = wp;
            }
        }
    }

    Timer {
        id: scrollTimer
        interval: 50
        onTriggered: {
            for (var i = 0; i < root.wallpapers.length; i++) {
                if (root.wallpapers[i].path === root.currentWallpaper) {
                    root.selectedIndex = i;
                    return;
                }
            }
        }
    }

    Process {
        id: previewProc
        property string wallpaperPath: ""
        command: ["swww", "img", wallpaperPath, "--resize", "crop", "--transition-type", "any", "--transition-duration", "0.4", "--transition-fps", "240"]
        running: false
    }

    Process {
        id: applyProc
        property string wallpaperPath: ""
        command: ["wallpaper", "-s", "set", wallpaperPath]
        running: false
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                root.moveSelection(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                root.moveSelection(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.commitSelection();
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                root.revertAndClose();
                event.accepted = true;
            }
        }

        Item {
            id: popupContent
            anchors.fill: parent

            ListView {
                id: gallery
                anchors.fill: parent
                anchors.margins: 8
                orientation: ListView.Vertical
                spacing: 28
                clip: true
                model: root.wallpapers.length
                currentIndex: root.selectedIndex

                preferredHighlightBegin: (height - root.cardHeight) / 2
                preferredHighlightEnd: (height + root.cardHeight) / 2
                highlightRangeMode: ListView.StrictlyEnforceRange
                highlightMoveDuration: 250
                cacheBuffer: 5000

                delegate: Item {
                    id: card
                    required property int index
                    width: gallery.width
                    height: root.cardHeight

                    property var entry: root.wallpapers[index]
                    property bool isFocused: index === root.selectedIndex

                    z: isFocused ? 2 : (cardMouse.containsMouse ? 1.5 : 1)
                    scale: isFocused ? 1.3 : (cardMouse.containsMouse ? 1.08 : 1.0)

                    Behavior on scale {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }

                    Item {
                        anchors.centerIn: parent
                        width: root.cardWidth
                        height: root.cardHeight
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.05)
                            visible: thumb.status !== Image.Ready
                        }

                        Image {
                            id: thumb
                            anchors.fill: parent
                            source: "file://" + entry.path
                            sourceSize.width: Math.round(root.cardWidth * 1.3)
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                        }
                    }

                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.currentWallpaper = entry.path;
                            root.originalWallpaper = entry.path;
                            applyProc.wallpaperPath = entry.path;
                            applyProc.running = true;
                            root.closed();
                        }
                    }
                }
            }

            // Scroll indicator
            Rectangle {
                id: scrollIndicator
                anchors.right: gallery.right
                anchors.rightMargin: 2
                width: 3
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.2)
                visible: gallery.contentHeight > gallery.height

                property real scrollRatio: gallery.contentY / (gallery.contentHeight - gallery.height)

                height: 40
                y: gallery.y + scrollRatio * (gallery.height - height)
            }
        }
    }
}
