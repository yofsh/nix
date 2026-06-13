---
name: qs
description: Use when working on quickshell — the QML status bar, widgets, popups in dotfiles/quickshell/ — or the qs-daemon backend. Covers architecture, module authoring, hot reload, daemon rules, and bundled dev scripts to screenshot popups, force reloads, and query the daemon. Trigger words: quickshell, qs, bar, widget, popup, qs-daemon, QML, shell.qml.
---

# Quickshell development

QML status bar + desktop widgets (`dotfiles/quickshell/`), fed by a Bun daemon
(`dotfiles/bin/utils/qs-daemon.d/`) over a unix socket. Dotfiles are symlinked —
no rebuild ever; changes apply via hot reload.

## Canonical docs — read before non-trivial work

| File | What's in it |
|---|---|
| `dotfiles/quickshell/README.md` | Structure, **component/helper catalogs** (ThemedText, DaemonFetch, Format.js, …), module format, widget/popup templates, popup-splitting convention, best-practice checklist, gotchas |
| `dotfiles/quickshell/CLAUDE.md` | Module registration steps (BarHost/ServiceHost wiring, keybind + submap), **hot-reload mechanics**, daemon cost rules (spawn-free ticks, worker threads), Process re-trigger pattern, Repeater sizing |
| `dotfiles/bin/README.md` | bin/ layout conventions (qs-daemon lives in `bin/utils/qs-daemon.d/`) |

## Architecture in brief

- **Statically linked, no manifest**: `core/BarHost.qml` instantiates every widget+popup (`BarWidget`/`BarPopup` shorthands), `core/ServiceHost.qml` every service. Adding a module = add files in `modules/<id>/` + explicit import/instantiation there.
- A module dir name **is** its id; files are `Widget.qml` / `Popup.qml` / `Service.qml` + UpperCamel section components for split popups (>~600 lines).
- `Popup.qml` is a plain content `Item` (`popupOpen`, `implicitWidth/Height`); `core/PackagePopup.qml` provides the window, placement under the bar, click-out close, and free `qs ipc call <id> open|close|toggle`.
- **Daemon-first data**: widgets are pure consumers of qs-daemon routes via `Helpers.DaemonFetch` (one-shot) / `Helpers.DaemonStream` (stream). Never spawn per-tick subprocesses in QML; missing field → add it to the daemon payload.
- Build UI only from `components/` + `helpers/` (catalogs in README.md). Theme defaults single-sourced in `config/Config.qml` — never `theme.x || fallback`.

## Dev scripts (bundled in this skill, `scripts/`)

Run from the repo root, e.g. `.claude/skills/qs/scripts/qs-popup weather`.

### qs-popup — screenshot a popup/bar with auto-detected geometry

Popup windows are layershell surfaces (namespace `quickshell`) that exist only
while open; the script diffs `hyprctl layers -j` across the open transition to
find the exact region, then `grim`s it.

```bash
scripts/qs-popup list                 # popup-capable module ids (from qs ipc show)
scripts/qs-popup weather              # open → wait → screenshot → close; prints png path
scripts/qs-popup network -d 2 -k      # slow-loading popup: 2s data delay, keep open
scripts/qs-popup network -r           # re-shoot cached region (after -k + interaction)
scripts/qs-popup bar [left|center|right] -z 3   # the visible bar block (or a third), 3× zoom
```

Then **Read the printed png** to verify layout/content visually. `-z N` upscales
via magick — use it for the bar and other small regions, they're unreadable at 1×.
Bar geometry comes from `qs ipc call bar geometry` (an IpcHandler in
`core/BarHost.qml` exposing the centered content block; the layer surface itself
spans the whole monitor).

### qs-reload — force hot reload / restarts, surface QML errors

Quickshell's watcher needs **inode-preserving writes**; the Edit tool renames on
save, so QML edits do NOT auto-reload. After editing, always:

```bash
scripts/qs-reload          # truncate-in-place touch of shell.qml → reload + log tail
scripts/qs-reload -l 50    # just the last 50 log lines (QML errors/warnings)
scripts/qs-reload -r       # full quickshell restart (handles session env + the
                           #   .quickshell-wra comm-name pitfall)
scripts/qs-reload -d       # restart qs-daemon (needed after editing qs-daemon.d/*.ts)
scripts/qs-reload -k       # refresh daemon keybind cache (after hyprctl reload)
```

### qs-route — query the qs-daemon socket

```bash
scripts/qs-route                  # health: module list, uptime
scripts/qs-route list             # every registered route
scripts/qs-route calendar/state   # GET + jq pretty-print
scripts/qs-route -s net/stream 3  # consume 3 lines of a stream, then exit
scripts/qs-route -p focus/toggle '{"x":1}'   # POST
```

## Standard verify loop for widget/popup work

1. Edit the module QML.
2. `scripts/qs-reload` — reload won't happen otherwise (Edit tool inode pitfall); check the log tail it prints for QML errors.
3. `scripts/qs-popup <id>` (or `qs-popup bar right`) and **Read the png**.
4. Iterate. For interaction states: `qs-popup <id> -k`, interact via `qs ipc call`, then `qs-popup <id> -r`.
5. Daemon changes (`qs-daemon.d/*.ts`): `scripts/qs-reload -d`, then `scripts/qs-route <route>` to verify payloads before touching QML.
6. New/changed hyprland binds: set a `description`, `hyprctl reload`, then `scripts/qs-reload -k`.

## Top gotchas (full list in README.md → Gotchas)

- Never name a property `data`/`children`/`state`/`focus` on Item types — `data` silently destroys all children.
- `ThemedText` defaults to popup body size — in **bar** widgets always set `font.pixelSize`.
- Keep file headers brace-free (a `{` in a comment above the root object kills the hot-reload import scan).
- `Process.running = true` is a no-op while in flight — use `DaemonFetch`, or copy its kill-and-restart pattern.
- Set Repeater sizing divisors **before** assigning the model.
- Restart pitfalls: quickshell's comm is `.quickshell-wra`; get `HYPRLAND_INSTANCE_SIGNATURE` via `find`/`hyprctl instances`, never icon-wrapped `ls` (qs-reload handles both).
- Benign startup noise: "Object or context destroyed during incubation" (INFO, per module) and qmlscanner "invalid characters" warnings — not errors.
