# Modular Quickshell Layout

Convention-based modules, **statically linked** — no runtime scan, no manifest. Modules are instantiated explicitly in `core/BarHost.qml` (widgets + popups) and `core/ServiceHost.qml` (services) via reusable wrappers that carry the shared boilerplate, so module files stay minimal. This is what lets module edits hot-reload in place (see `~/nix/CLAUDE.md` → Quickshell → Hot reload).

## Structure

- `core/`: runtime — config loading (`ConfigService`), the static hosts (`BarHost`, `ServiceHost`), the wrappers (`PackageWidget` / `PackagePopup` / `PackageService`), popup state (`PopupService` / `PopupController` / `ModuleContext`), and a live-instance registry (`ModuleRegistry`)
- `modules/`: modules, each in its own directory (folder name = module id)
- `popups/`: system-level popups (notifications, OSD, fingerprint, polkit)
- `config/shell.json`: public config (committed) — theme + per-module config (the bar *layout* is static QML in `BarHost`, not here)
- `config/private.json`: local private overrides (gitignored)

## Module Format

Each module is a directory under `modules/`. The directory name is the module ID.

Well-known filenames:

- `Widget.qml` - bar widget
- `Popup.qml` - popup window
- `Service.qml` - background service with custom IPC or state

A module can have any combination of these. Examples:

```
modules/cpu/Widget.qml                  # widget only
modules/battery/Widget.qml + Popup.qml  # widget + popup
modules/wallpaper/Popup.qml             # popup only
modules/network/Widget.qml + Service.qml  # widget + custom IPC
```

## Auto-IPC

`PackagePopup` gives every popup `toggle`/`open`/`close` IPC for free — no `Service.qml` needed for basic popup control:

```bash
qs ipc call battery toggle
qs ipc call wallpaper open
```

Only create `Service.qml` when a module has custom IPC beyond popup control (e.g. `network` has pin/unpin, `ping` has fast/normal). If that service defines its own `IpcHandler` for the module's target, set `ipc: false` on its `PackagePopup` so the two don't both register the same target.

## Config

`config/shell.json` holds the theme and per-module config. The **bar layout is static QML** in `core/BarHost.qml` (the order you write the `PackageWidget`s is the order on the bar) — there is no `bar` list in `shell.json`.

```json
{
  "modules": {
    "weather": { "enabled": false }
  }
}
```

Per-module config is available via `context.config` inside modules (merged from `shell.json` + `private.json`).

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

**Wire it up** — in `core/BarHost.qml`:
```qml
import "../modules/my-counter" as M_my_counter
// ...in a section:
Core.PackageWidget { moduleId: "my-counter"; screen: hostScreenInfo; M_my_counter.Widget {} }
```
and in `core/ServiceHost.qml`:
```qml
import "../modules/my-counter" as M_my_counter
Core.PackageService { moduleId: "my-counter"; M_my_counter.Service {} }
```

**Config** (in `config/shell.json`, optional):
```json
{ "modules": { "my-counter": { "label": "ticks", "intervalMs": 500 } } }
```

## Creating a Widget

A widget is a bar component. Create `modules/<name>/Widget.qml`:

```qml
import QtQuick
import Quickshell.Io
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root
    implicitWidth: Math.max(24, label.implicitWidth + 6)
    implicitHeight: parent ? parent.height : 30

    property var context: null
    property bool popupOpen: false   // required if this widget has a Popup.qml

    // Your state
    property string displayText: "—"

    // Load data via Process
    Process {
        id: loadProc
        command: ["your-command", "args"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    // update your properties from d
                } catch (e) {}
            }
        }
    }

    // Periodic refresh
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: loadProc.running = true
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.displayText
        color: Helpers.Colors.textDefault
        font.family: AppConfig.Config.theme.fontFamily
        font.pixelSize: AppConfig.Config.theme.fontSizeDefault
    }

    // Click to toggle popup (only if module has a Popup.qml)
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.popupOpen = !root.popupOpen
    }
}
```

Key points:
- `popupOpen` property: declare it if the widget has a companion `Popup.qml` — `PackagePopup` reads it to show/hide the popup, and its presence also marks the widget as **interactive** (hover highlight + pointer cursor). A widget that opens its popup via `context.togglePopup()` instead (no `popupOpen`) should set `property bool interactive: true`.
- `context` is set by `PackageWidget` and gives access to `context.service`, `context.config`, `context.theme`, `context.togglePopup()`, etc.
- `implicitWidth` drives how much space the widget takes in the bar.

## Creating a Popup

A `Popup.qml` is **just the content** — a plain `Item`. `Core.PackagePopup` (instantiated in `BarHost`) provides the window, top-of-bar placement, `visible`/open-close state, click-outside-to-close and IPC. Create `modules/<name>/Popup.qml`:

```qml
import QtQuick
import QtQuick.Controls
import "../../helpers" as Helpers
import "../../components" as Components
import "../../config" as AppConfig

Item {
    id: root

    // Wired by PackagePopup (declare only what you use):
    property var context: null       // context.config / context.service / ...
    property bool popupOpen: false    // mirrors the wrapper's open state

    implicitWidth: 400                // drives the popup window's size
    implicitHeight: 500

    // Your state properties here

    onPopupOpenChanged: {
        if (popupOpen) loadProc.running = true;   // lazy-load when shown
    }

    // Data loading (Process, Timer, etc.) goes here

    // Background — themed surface, or a plain Rectangle
    Components.PopupSurface { anchors.fill: parent }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        Text {
            text: "My Popup"
            color: Helpers.Colors.textDefault
            font.family: AppConfig.Config.theme.fontFamily
            font.pixelSize: AppConfig.Config.theme.fontSizeMedium
            font.bold: true
        }
        // your content...
    }
}
```

Key points:
- Root is an **`Item`**, not a `PanelWindow`. No `anchors`/`margins`/`visible`/`color`/`barHeight` — `PackagePopup` owns all of that. (Need `screen` for sizing? Declare `property var screen: null`; the wrapper sets it.)
- `property var context` / `property bool popupOpen` are set by the wrapper — declare them only if you use them.
- `implicitWidth`/`implicitHeight` size the popup window.
- Then wire it once in `BarHost` (see **Registering a Module**).
- **Exception:** a popup that needs its own surface (e.g. `wallpaper` uses `WlrLayershell` keyboard focus) stays a `PanelWindow` and wires its own state/IPC — don't wrap those in `PackagePopup`.

## Registering a Module

Wiring is explicit and static (no `shell.json` bar list, no auto-discovery).

1. Place your files in `modules/<name>/`.
2. In `core/BarHost.qml`, add the import once: `import "../modules/<name>" as M_<name>`, then:
   - **widget** → `Core.PackageWidget { moduleId: "<name>"; screen: hostScreenInfo; M_<name>.Widget {} }` in the `leftSection`/`centerSection`/`rightSection` at the position you want.
   - **popup** → `Core.PackagePopup { moduleId: "<name>"; screen: hostScreenInfo; barWindow: barWindow; M_<name>.Popup {} }` with the other popups (`ipc: false` if the service owns IPC; `keyboardFocus: true` if it takes typed input).
3. **Service** → in `core/ServiceHost.qml`, add the import and `Core.PackageService { moduleId: "<name>"; M_<name>.Service {} }`.
4. Reload quickshell (`SUPER+CTRL+SHIFT+W`). No rebuild needed (dotfiles are symlinked).

A popup-only module (no bar widget) just gets a `PackagePopup` in step 2 and is opened by IPC/keybind (e.g. `qs ipc call <name> toggle`).

## Keeping modules maintainable & reusable

The whole point of the wrappers is that **shared behavior lives in one place** — keep it that way:

- **Put cross-cutting logic in the wrapper, not the module.** Window placement, open/close state, click-out, IPC, hover/cursor, context wiring all live in `PackageWidget` / `PackagePopup` / `PackageService`. If you find yourself copy-pasting the same block into several modules, it belongs in the wrapper (add a property/flag like `ipc` or `keyboardFocus`) — not in each `Popup.qml`.
- **Modules should be "dumb content."** A `Widget.qml`/`Popup.qml` should describe *what it shows*, reading inputs via `context` (`context.config`, `context.service`, `context.theme`) and exposing state via the agreed contract (`popupOpen`, `interactive`, `implicitWidth/Height`). Avoid reaching into `core` singletons directly from a module; go through `context`.
- **Read config/theme through `context` / `AppConfig.Config`**, never hardcode colors, sizes, or paths. New theme keys go in `shell.json` and are picked up live.
- **Folder = id, files = `Widget`/`Popup`/`Service`.** Don't invent other filenames; the wrappers and imports rely on this. One concern per file.
- **Prefer static over `Loader`.** Dynamic `Loader { source }` breaks hot-reload state-matching and isn't watched by the scanner (see the `cpu`-in-`system-group` caveat in CLAUDE.md). Statically `import` + instantiate instead.
- **Keep import-heavy headers brace-free** (see gotchas) and **declare only the `context`/`popupOpen`/`screen` properties you actually use** — the wrapper sets them conditionally (`"x" in body`), so unused ones are just noise.
- When something is genuinely an exception (e.g. `wallpaper`'s own `WlrLayershell` window), keep it self-contained and clearly commented rather than bending a wrapper to fit one case.

## Gotchas

### `property var data` — reserved name

**Never name a property `data`** on a PanelWindow (or any Item-based type). `data` is a built-in QML default property that holds all child objects. Overriding it with `property var data: null` silently destroys the child list, causing **all content to disappear** with no error message.

Use a descriptive name instead:
```qml
// BAD — breaks all children
property var data: null

// GOOD
property var usageData: null
property var eventData: null
property var responseJson: null
```

### PanelWindow `color` / content-wrapping (now handled by `PackagePopup`)

These two used to bite every popup; `PackagePopup` now handles them, so a normal content-`Item` popup doesn't need to care. They still apply if you write a **standalone `PanelWindow`** popup (the `wallpaper` exception):

- **`color` must be `"transparent"`** — an opaque PanelWindow `color` paints the surface *above* the content, hiding everything. Set `color: "transparent"` and draw your background as the first child.
- **Wrap content in `Item { anchors.fill: parent }`** — direct PanelWindow children may not render.

### MouseArea cursor in modules

Module-level `MouseArea` elements intercept hover before the core `HoverHandler`. If your widget uses a `MouseArea`, set `cursorShape` locally:
```qml
MouseArea {
    cursorShape: Qt.PointingHandCursor   // set this explicitly
}
```

### Other reserved/conflicting property names

Avoid these names for custom properties on Item-based types:
- `data` — default child list
- `children` — visual children list
- `resources` — non-visual children
- `state` / `states` — state machine
- `transitions` — state transitions
- `parent` — visual parent
- `focus` — built-in `bool` (active keyboard focus). Also bites **methods**: a `function focus(...)` on an Item collides with the property, so `root.focus(x)` reads the bool instead of calling it and silently fails. Name the method something else (e.g. `focusSession`).
