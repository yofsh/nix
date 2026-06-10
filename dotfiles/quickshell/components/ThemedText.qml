import QtQuick
import "../helpers" as Helpers
import "../config" as AppConfig

// Text with the theme font and default color pre-applied — use this instead of
// a bare Text everywhere the theme font is wanted (i.e. almost everywhere).
// Override `font.pixelSize` / `color` / `font.bold` as usual; set `muted: true`
// for secondary text instead of binding color manually.
Text {
    property bool muted: false

    color: muted ? Helpers.Colors.textMuted : Helpers.Colors.textDefault
    font.family: AppConfig.Config.theme.fontFamily
    font.pixelSize: AppConfig.Config.theme.popupFontSizeBody
}
