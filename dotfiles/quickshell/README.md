# Modular Quickshell Layout

Convention-based module system. No manifests, no boilerplate.

## Structure

- `Core/`: runtime (config loading, module discovery, popup control, service hosting)
- `modules/`: built-in modules, each in its own directory
- `Plugins/`: drop-in third-party modules (same structure as `modules/`)
- `popups/`: system-level popups (notifications, OSD, fingerprint, polkit)
- `Config/shell.json`: public config (committed)
- `Config/private.json`: local private overrides (gitignored)

## Module Format

Each module is a directory under `modules/` or `Plugins/`. The directory name is the module ID.

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

Bar layout is driven by `Config/shell.json`:

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

## Adding a Plugin

1. Create `Plugins/<id>/` with `Widget.qml`, `Popup.qml`, and/or `Service.qml`
2. Add the module ID to `Config/shell.json`
3. Restart Quickshell

See [`Plugins/example-counter`](./Plugins/example-counter/README.md) for a working example.
