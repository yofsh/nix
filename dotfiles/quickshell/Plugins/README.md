# Plugins

Drop third-party modules into this directory.

Each plugin is a directory containing one or more of:
- `Widget.qml` - bar widget
- `Popup.qml` - popup window
- `Service.qml` - background service with custom IPC

The directory name is the module ID. Add the ID to `bar.left`/`center`/`right` in `Config/shell.json`.

Quickshell only scans on startup, so restart after adding or removing a plugin.

See [`example-counter`](./example-counter/README.md) for a minimal plugin with a service and a bar widget.
