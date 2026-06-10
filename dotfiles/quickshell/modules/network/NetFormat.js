.pragma library

// Network-module formatters shared by more than one section file.
// Single-section formatters live in their section's file.

// Wi-Fi generation badge color. Returns "" for unknown/legacy generations so
// callers can fall back to the theme's muted text color.
function genColor(g) {
    if (g === "7")
        return "#bb86fc";
    if (g === "6E")
        return "#4dd0e1";
    if (g === "6")
        return "#66bb6a";
    if (g === "5")
        return "#ffa726";
    if (g === "4")
        return "#ef5350";
    return "";
}
