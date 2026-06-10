import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

// Live-day status rows: time-without-break streak, breaks today, and the
// currently focused window. Reads the popup root directly — it needs 10+
// bindings (isLive/onBreak/streak*/break*/current/categories + formatters).
Column {
    id: root

    required property var popup

    spacing: 12

    // ── Time without break ───────────────────────────────────────────────
    Row {
        width: parent.width
        spacing: 8
        visible: root.popup.isLive

        Components.ThemedText {
            text: root.popup.onBreak ? "" : ""
            color: {
                if (root.popup.onBreak) return Helpers.Colors.textMuted;
                if (root.popup.streakSeconds >= 4500) return Helpers.Colors.mutedRed;
                if (root.popup.streakSeconds >= 2700) return "#ffb74d";
                return Helpers.Colors.accent;
            }
            anchors.verticalCenter: parent.verticalCenter
        }
        Components.ThemedText {
            text: root.popup.onBreak ? "On a break" : "Time without break"
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: 1; height: 1 }
        Components.ThemedText {
            visible: !root.popup.onBreak
            text: root.popup.formatTime(root.popup.streakSeconds) + (root.popup.streakSince ? "  ·  since " + root.popup.clock(root.popup.streakSince) : "")
            muted: true
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ── Breaks today ─────────────────────────────────────────────────────
    Row {
        width: parent.width
        spacing: 8
        visible: root.popup.isLive && root.popup.breakCount > 0

        Components.ThemedText {
            text: "" // coffee cup
            muted: true
            anchors.verticalCenter: parent.verticalCenter
        }
        Components.ThemedText {
            text: root.popup.breakCount + (root.popup.breakCount === 1 ? " break today" : " breaks today")
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: 1; height: 1 }
        Components.ThemedText {
            visible: root.popup.lastBreak !== null
            text: {
                if (!root.popup.lastBreak) return "";
                var dur = root.popup.formatTime(root.popup.lastBreak.seconds);
                if (root.popup.lastBreak.ongoing)
                    return "current " + dur + (root.popup.lastBreak.since ? "  ·  since " + root.popup.clock(root.popup.lastBreak.since) : "");
                return "last " + dur + (root.popup.lastBreak.since ? "  ·  at " + root.popup.clock(root.popup.lastBreak.since) : "");
            }
            color: root.popup.lastBreak && root.popup.lastBreak.ongoing ? Helpers.Colors.accent : Helpers.Colors.textMuted
            font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // ── Current window ───────────────────────────────────────────────────
    Row {
        width: parent.width
        spacing: 8
        visible: root.popup.current !== null && root.popup.current !== undefined

        Rectangle {
            width: 3
            height: 34
            radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: {
                if (!root.popup.current) return Helpers.Colors.textMuted;
                var cats = root.popup.categories;
                for (var i = 0; i < cats.length; i++)
                    if (cats[i].name === root.popup.current.category) return cats[i].color;
                return Helpers.Colors.textMuted;
            }
        }

        Column {
            spacing: 2
            anchors.verticalCenter: parent.verticalCenter
            Components.ThemedText {
                text: root.popup.current ? (root.popup.current["class"] || "") + "  " + (root.popup.current.category || "") + " · " + (root.popup.current.subcategory || "") : ""
            }
            Components.ThemedText {
                width: root.width - 24
                text: root.popup.current ? ((root.popup.current.title || "").length > 70 ? (root.popup.current.title || "").substring(0, 70) + "…" : (root.popup.current.title || "")) : ""
                muted: true
                font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
                elide: Text.ElideRight
            }
        }
    }
}
