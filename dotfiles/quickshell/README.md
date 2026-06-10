# Modular Quickshell Layout

Status bar + desktop widgets. Convention-based modules, **statically linked** — no runtime scan, no manifest. Modules are instantiated explicitly in `core/BarHost.qml` (widgets + popups) and `core/ServiceHost.qml` (services) via reusable wrappers that carry the shared boilerplate, so module files stay minimal. Static linking is also what makes module edits hot-reload in place (see `CLAUDE.md` → Hot reload).

## Structure

- `core/` — runtime: config loading (`ConfigService`), the static hosts (`BarHost`, `ServiceHost`), the wrappers (`PackageWidget` / `PackagePopup` / `PackageService`), popup state (`PopupService` / `PopupController` / `ModuleContext`), live-instance registry (`ModuleRegistry`), submap cheatsheet (`SubmapOverlay`)
- `components/` — visual building blocks shared by all modules (catalog below)
- `helpers/` — non-visual building blocks: data fetching, formatting, color/config singletons (catalog below)
- `modules/` — modules, one directory each (folder name = module id)
- `popups/` — system-level popups (notifications, OSD, fingerprint, polkit); standalone `PanelWindow`s, exceptions to the module pattern
- `config/shell.json` — public config (committed): theme + per-module config. `config/private.json` — local private overrides (gitignored). `config/Config.qml` — typed accessor **and the single source of theme defaults**

## Shared building blocks

Use these instead of hand-rolling. If you need a variant, add a property to the shared component — don't copy it into your module.

### components/ (import `"../../components" as Components` from a module)

| Component | What it is |
|---|---|
| `ThemedText` | `Text` with theme font + default color pre-applied. `muted: true` for secondary text. Default size is `popupFontSizeBody` — **always set `font.pixelSize` explicitly in bar widgets** (bar uses the smaller `fontSize*` keys). |
| `SectionLabel` | Muted bold section header ("Usage limits", "Recent"). |
| `Divider` | The standard 1px separator (`Qt.rgba(1,1,1,0.08)`). |
| `PopupHeader` | Popup title row: accent title left, trailing children right-aligned. |
| `ActionButton` | Standard button: subtle idle fill, accent hover, pointer cursor. `label`, `clicked()`, inherited `enabled` dims it. |
| `ToggleChip` | Pill state chip: accent-tinted when `active`. `label`, `toggled()`. |
| `PopupFlick` | Scrollable popup body: Flickable + as-needed scrollbar wrapping a Column (children land in the Column; `spacing` passes through). |
| `IconLabel` | Bar-widget icon + label pair; either part hides when empty. |
| `PopupSurface` | Themed popup background surface. |
| `StatDots` | Dot-separated row of stat strings with uniform padding. |

New components go in `components/` **and must be registered in `components/qmldir`**.

### helpers/ (import `"../../helpers" as Helpers`)

| Helper | What it is |
|---|---|
| `DaemonFetch` | One-shot JSON fetch from the qs-daemon socket (`path: "/route"`) or a plain URL (`url:`). Has the canonical kill-and-restart + stale-response guard built in: bind `path` to a reactive route and navigation auto-refetches safely; call `reload()` for manual refresh. `active:` gates it (bind to `popupOpen` for lazy popups), `intervalMs` polls, `method`/`body` for POST, `onJson`/`onFailed`/`busy`. No custom headers — auth'd HTTP (e.g. Home Assistant) stays a plain `Process`. |
| `DaemonStream` | Long-lived `curl -sN` line stream from the daemon socket with 1s-backoff auto-reconnect. `onLine` gets parsed JSON per line; `onRawLine` for non-JSON streams. |
| `Format.js` | Canonical formatters (import `"../../helpers/Format.js" as Format`): `bytes`, `rate`, `hoursMinutes` ("1h23m"), `clock` ("1:35"), `hourClock` ("1:30"), `tokens` ("1.2M"), `cost` ("$12.3"), `pct`, `timeAgo`. Generic formatting belongs here; domain-specific formatting (khal countdowns, wifi bitrates) stays in the module. |
| `Colors` | Typed singleton over `theme.colors.*` — preferred accessor: `Helpers.Colors.accent`, not `theme.colors.accent`. |
| `ModuleConfig` | Per-module config defaults + normalization (feeds `context.config`). |
| `ShellCommand` | Tiny Process+Timer poller for a shell command's stdout. |

Theme values: `AppConfig.Config.theme.*` (and `context.theme`) **always carry full defaults** — defaults are declared once in `config/Config.qml`. Never write `theme.x || fallback`; if a key is new, add its default to `Config.qml`.

## Module Format

Each module is a directory under `modules/`; the directory name is the module ID. Well-known filenames:

- `Widget.qml` — bar widget
- `Popup.qml` — popup content
- `Service.qml` — background service with custom IPC or state

A module can have any combination. Big popups are split into additional **section components** in the same directory (`WifiCard.qml`, `ForecastChart.qml`, …) — same-directory QML types resolve automatically, no import needed. Examples:

```
modules/cpu/Widget.qml                    # widget only
modules/battery/Widget.qml + Popup.qml    # widget + popup
modules/wallpaper/Popup.qml               # popup only
modules/network/Popup.qml + WifiCard.qml + BluetoothCard.qml + …   # split popup
```

## Module Context

Widgets, services, and popups can declare a `property var context` to receive:

- `context.moduleId`, `context.screen`
- `context.theme` (full defaults), `context.config` / `context.privateConfig`
- `context.service`
- `context.openPopup()` / `context.closePopup()` / `context.togglePopup()`

Declare only the properties you actually use — the wrappers set them conditionally (`"x" in body`).

## Auto-IPC

`PackagePopup` gives every popup `toggle`/`open`/`close` IPC for free:

```bash
qs ipc call battery toggle
```

Only create `Service.qml` for custom IPC beyond popup control (e.g. `network`). If the service defines its own `IpcHandler` for the module's target, set `ipc: false` on its `BarPopup` entry so they don't both register the target.

## Registering a Module

Wiring is explicit and static (no `shell.json` bar list, no auto-discovery). `BarHost` defines two inline shorthands — `BarWidget` / `BarPopup` — that pre-wire `screen` and `barWindow`:

1. Put your files in `modules/<name>/`.
2. In `core/BarHost.qml`, add `import "../modules/<name>" as M_<name>` at the top, then:
   - **widget** → `BarWidget { moduleId: "<name>"; M_<name>.Widget {} }` in `leftSection`/`centerSection`/`rightSection` (order = bar position)
   - **popup** → `BarPopup { moduleId: "<name>"; M_<name>.Popup {} }` with the other popups (`ipc: false` if the service owns IPC; `keyboardFocus: true` if it takes typed input)
3. **Service** → in `core/ServiceHost.qml`: add the import and `Core.PackageService { moduleId: "<name>"; M_<name>.Service {} }`.
4. Reload quickshell (`SUPER+CTRL+SHIFT+W`). No rebuild needed (dotfiles are symlinked).
5. If the module has a popup, wire its keybind + submap entry (see `CLAUDE.md` → Adding a module, steps 6–7).

A popup-only module skips the widget and is opened by IPC/keybind.

## Creating a Widget

```qml
import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../config" as AppConfig

Item {
    id: root

    property var context: null
    property bool popupOpen: false   // only if the module has a Popup.qml

    implicitWidth: label.implicitWidth + 6
    implicitHeight: parent ? parent.height : 30

    property string displayText: "—"

    Helpers.DaemonFetch {
        path: "/my-route/state"
        intervalMs: 30000
        onJson: data => root.displayText = data.value || "—"
    }

    Components.ThemedText {
        id: label
        anchors.centerIn: parent
        text: root.displayText
        font.pixelSize: AppConfig.Config.theme.fontSizeDefault   // bar size, not the popup default
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor   // module MouseAreas set this locally
        onClicked: root.popupOpen = !root.popupOpen
    }
}
```

Key points:
- `popupOpen`: declare it if the widget has a companion `Popup.qml` — `PackagePopup` reads it, and its presence marks the widget **interactive** (hover highlight + pointer cursor). A widget that opens its popup via `context.togglePopup()` instead sets `property bool interactive: true`.
- `implicitWidth` drives bar space; collapse to 0 when hidden (`implicitWidth: visible ? … : 0`).

## Creating a Popup

A `Popup.qml` is **just the content** — a plain `Item`. `BarPopup` (→ `Core.PackagePopup`) provides the window, placement, open/close state, click-outside-close and IPC.

```qml
import QtQuick
import "../../components" as Components
import "../../helpers" as Helpers
import "../../helpers/Format.js" as Format

Item {
    id: root

    property var context: null
    property bool popupOpen: false    // mirrors the wrapper's open state

    implicitWidth: 400                // drives the popup window's size
    implicitHeight: 500

    property var entries: []

    Helpers.DaemonFetch {
        id: fetcher
        path: "/my-route/details"
        active: root.popupOpen        // lazy: fetch on open, nothing while closed
        intervalMs: 15000
        onJson: data => root.entries = data.entries || []
    }

    Components.PopupSurface { anchors.fill: parent }

    Components.PopupFlick {
        anchors.fill: parent
        anchors.margins: 16

        Components.PopupHeader {
            title: " My Module"
            Components.ToggleChip { label: "7 days"; active: false; onToggled: fetcher.reload() }
        }
        Components.Divider {}

        Components.SectionLabel { text: "Entries" }
        Components.ThemedText { visible: root.entries.length === 0; muted: true; text: "Nothing yet" }
        // rows / charts / Repeaters here — Format.bytes(...), Format.timeAgo(...) for values

        Components.ActionButton { label: "Refresh"; onClicked: fetcher.reload() }
    }
}
```

Key points:
- Root is an **`Item`**, not a `PanelWindow` — no anchors/visible/color; the wrapper owns those. (Need `screen` or `barHeight`? Declare the property; the wrapper sets it.)
- **Exception:** a popup needing its own surface (e.g. `wallpaper`'s WlrLayershell keyboard focus) stays a `PanelWindow` and wires its own state/IPC.

## Splitting large popups

When a popup grows past **~600 lines**, split it into section components in the module directory (see `network/`, `weather/`, `app-usage/` as references):

- `Popup.qml` stays the **composition root**: public contract (`context`, `popupOpen`, `implicitWidth/Height`), shared state, all `DaemonFetch`/`DaemonStream` instances, section layout.
- Sections are same-directory `UpperCamel.qml` files — auto-resolved, watched, hot-reloaded. Data flows **in via explicit properties**, actions **out via signals** (or calls on a passed root). If a section genuinely needs >8 bindings, passing the popup root as one `property var popup` is acceptable.
- An inline `component Foo:` used by several sections gets its own file; used by one section, it moves with that section.
- Don't split fragments under ~100 lines.

## Best practices (new widgets / functionality)

1. **Daemon-first data.** System/network/process state comes from qs-daemon streams — widgets are pure consumers via `DaemonStream`/`DaemonFetch`. Never spawn per-tick subprocesses client-side; if a field is missing, add it to the daemon payload (see `CLAUDE.md` → Daemon).
2. **Lazy popups.** Gate popup fetching with `active: root.popupOpen`. Bar widgets poll slowly; popups fetch on open.
3. **Reuse before writing.** Check the catalogs above. The same block twice = extract it: module-specific → section component in the module dir; cross-module visual → `components/`; cross-cutting behavior (placement, IPC, state) → the `core/` wrappers.
4. **Theme through the system.** No hardcoded fonts/colors/sizes: `ThemedText`, `Helpers.Colors.*`, `theme.*` keys. New theme keys get a default in `config/Config.qml` first, then an entry in `shell.json` if it should differ.
5. **Generic formatting in `Format.js`**, domain formatting local. Don't re-implement `bytes`/durations.
6. **Modules are dumb content.** Read inputs via `context`, expose the agreed contract (`popupOpen`, `interactive`, implicit sizes). Don't reach into `core` singletons from modules.
7. **Prefer static over `Loader`.** Dynamic `Loader { source }` breaks hot-reload matching and file watching. Statically import + instantiate.
8. **Stay within the file-layout convention.** Folder = id; `Widget`/`Popup`/`Service` + UpperCamel section files. New shared components/helpers must be added to the dir's `qmldir`.
9. **Exceptions stay self-contained.** If something genuinely can't use a wrapper (wallpaper, system popups), keep it isolated and commented — don't bend the wrapper around one case.

## Gotchas

### Reserved/conflicting property names

Never name custom properties on Item-based types: `data` (silently destroys all children!), `children`, `resources`, `state`, `states`, `transitions`, `parent`, `focus`. `focus` also bites **methods**: `function focus(...)` collides with the bool property and silently fails — name it e.g. `focusSession`.

### ThemedText sizing

`ThemedText` defaults to `popupFontSizeBody`. In bar widgets always set `font.pixelSize` (e.g. `theme.fontSizeDefault`); in popups you may omit it only when body size is wanted.

### Theme defaults live in Config.qml

`theme.x || fallback` chains are dead code — `AppConfig.Config.theme` / `context.theme` always merge full defaults. Add new keys to `config/Config.qml`.

### MouseArea cursor in modules

Module-level `MouseArea`s intercept hover before the core `HoverHandler` — set `cursorShape: Qt.PointingHandCursor` locally.

### PanelWindow `color` / content wrapping (standalone popups only)

Handled by `PackagePopup` for normal popups. Standalone `PanelWindow`s (wallpaper, system popups) must set `color: "transparent"` (opaque paints **over** the content) and wrap content in `Item { anchors.fill: parent }`.

### Bind-before-build for Repeater sizing divisors

Set a shared divisor property **before** assigning the model (`weekMax = computed; weekDays = data;`), as a plain property — not a lazy `readonly` binding — or delegates flash at the wrong size.

### Re-triggering a Process

`Process.running = true` is a **no-op while a run is in flight** — user-driven refetches get dropped or land stale. `DaemonFetch` implements the fix (kill + restart-next-tick + stale-guard); for non-daemon `Process`es that need user-driven refetch, copy the pattern from `CLAUDE.md` → "Re-triggering a Process".

### Header brace rule

Keep the import region of every file brace-free — a `{` in a comment above the root object (even inside a shell snippet) silently stops the hot-reload scanner's import parsing.
