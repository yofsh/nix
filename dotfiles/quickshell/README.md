# Modular Quickshell Layout

Convention-based module system. No manifests, no boilerplate.

## Structure

- `Core/`: runtime (config loading, module discovery, popup control, service hosting)
- `modules/`: built-in modules, each in its own directory
- `popups/`: system-level popups (notifications, OSD, fingerprint, polkit)
- `config/shell.json`: public config (committed)
- `config/private.json`: local private overrides (gitignored)

## Module Format

Each module is a directory under `modules/`. The directory name is the module ID.

Well-known filenames:

- `Widget.qml` - bar widget
- `Popup.qml` - popup window
- `Service.qml` - background service with custom IPC or state

A module can have any combination of these. Examples:

```
modules/clock/Widget.qml                # widget only
modules/battery/Widget.qml + Popup.qml  # widget + popup
modules/wallpaper/Popup.qml             # popup only
modules/network/Widget.qml + Service.qml  # widget + custom IPC
```

## Auto-IPC

Any module with a `Popup.qml` automatically gets IPC handlers for `toggle`, `open`, and `close`. No `Service.qml` needed for basic popup control:

```bash
qs ipc call battery toggle
qs ipc call wallpaper open
```

Only create `Service.qml` when the module has custom IPC beyond popup control (e.g., `network` has pin/unpin, `ping` has fast/normal).

## Config

Bar layout is driven by `config/shell.json`:

```json
{
  "bar": { "left": [...], "center": [...], "right": [...] },
  "modules": {
    "weather": { "enabled": false },
    "wallpaper": { "enabled": true, "alwaysLoadPopup": true }
  }
}
```

Per-module config is available via `context.config` inside modules.

## Module Context

Widgets, services, and popups can declare a `property var context` to receive:

- `context.moduleId`
- `context.screen`
- `context.theme`
- `context.config` / `context.privateConfig`
- `context.service`
- `context.openPopup()` / `context.closePopup()` / `context.togglePopup()`

## Example Plugin

A minimal counter module showing Widget + Service with config:

**Widget.qml**
```qml
import QtQuick

Item {
    id: root
    property var context
    readonly property var service: context ? context.service : null
    readonly property var theme: context ? context.theme : ({})
    readonly property var config: context ? context.config : ({})

    implicitWidth: label.implicitWidth + 4
    implicitHeight: parent ? parent.height : 22

    Text {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        text: (root.config.label || "example") + ": " + (root.service ? root.service.value : 0)
        color: theme.colors && theme.colors.textMuted ? theme.colors.textMuted : "white"
        font.family: theme.fontFamily || "DejaVuSansM Nerd Font"
        font.pixelSize: theme.fontSizeSmall || 10
    }
}
```

**Service.qml**
```qml
import Quickshell
import QtQuick

Scope {
    id: root
    property var context
    property int value: 0

    Timer {
        interval: root.context ? (root.context.config.intervalMs || 1000) : 1000
        running: true
        repeat: true
        onTriggered: root.value += 1
    }
}
```

**Config** (in `config/shell.json`):
```json
{
  "bar": { "right": ["my-counter"] },
  "modules": { "my-counter": { "enabled": true, "label": "ticks", "intervalMs": 500 } }
}
```
