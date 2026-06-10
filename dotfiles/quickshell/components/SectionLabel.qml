import QtQuick
import "../config" as AppConfig

// Muted bold section header ("Usage limits", "Recent", ...).
ThemedText {
    muted: true
    font.bold: true
    font.pixelSize: AppConfig.Config.theme.popupFontSizeSmall
}
