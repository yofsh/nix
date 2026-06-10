import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Usage breakdowns: per-category gradient bars with subcategory rows,
// followed by the top-apps list.
Column {
    id: root

    property var categories: []
    property var topApps: []
    property var fmtTime: null   // shared formatTime(seconds) from the popup

    spacing: 12

    // ── Categories ───────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 10

        Repeater {
            model: root.categories
            delegate: Column {
                required property var modelData
                width: parent.width
                spacing: 4

                Item {
                    width: parent.width
                    height: 22

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Components.ThemedText {
                            text: modelData.icon || ""
                            color: modelData.color || Helpers.Colors.textMuted
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeDefault
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Components.ThemedText {
                            text: modelData.name || ""
                            color: modelData.color || Helpers.Colors.textDefault
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Components.ThemedText {
                        anchors.right: catPctText.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.fmtTime(modelData.seconds)
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    }
                    Components.ThemedText {
                        id: catPctText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.percent || 0) + "%"
                        muted: true
                        font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                        width: 42
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Item {
                    width: parent.width
                    height: 8

                    Rectangle {
                        width: Math.max(0, parent.width * ((modelData.percent || 0) / 100)) + 6
                        height: 12
                        x: -3
                        y: -2
                        radius: 6
                        color: modelData.color || "#585b70"
                        opacity: 0.1
                    }

                    Rectangle {
                        width: parent.width
                        height: 5
                        y: 1
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    Rectangle {
                        width: Math.max(0, parent.width * ((modelData.percent || 0) / 100))
                        height: 5
                        y: 1
                        radius: 3

                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: modelData.color || "#585b70" }
                            GradientStop { position: 1.0; color: Qt.darker(modelData.color || "#585b70", 1.5) }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            radius: 1
                            color: "#ffffff"
                            opacity: 0.15
                        }

                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }

                Repeater {
                    model: modelData.subcategories || []
                    Row {
                        required property var modelData
                        width: parent.width
                        spacing: 6

                        Item { width: 20; height: 1 }

                        Components.ThemedText {
                            text: modelData.icon || ""
                            color: Qt.rgba(1, 1, 1, 0.35)
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            width: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Components.ThemedText {
                            text: modelData.name || ""
                            color: Qt.rgba(1, 1, 1, 0.5)
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            width: 120
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Components.ThemedText {
                            text: root.fmtTime(modelData.seconds)
                            muted: true
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Components.ThemedText {
                            text: (modelData.percent || 0) + "%"
                            color: Qt.rgba(1, 1, 1, 0.2)
                            font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }

    Components.Divider {}

    // ── Top Apps ─────────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 5

        Components.SectionLabel { text: "Top Apps" }

        Repeater {
            model: root.topApps.length > 5 ? root.topApps.slice(0, 5) : root.topApps
            Row {
                required property var modelData
                width: parent.width
                spacing: 10

                Components.ThemedText {
                    text: modelData["class"] || ""
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    width: 160
                    elide: Text.ElideRight
                    anchors.verticalCenter: parent.verticalCenter
                }
                Components.ThemedText {
                    text: root.fmtTime(modelData.seconds)
                    color: Qt.rgba(1, 1, 1, 0.6)
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
                Components.ThemedText {
                    text: modelData.category || ""
                    muted: true
                    font.pixelSize: AppConfig.Config.theme.popupFontSizeXSmall
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
