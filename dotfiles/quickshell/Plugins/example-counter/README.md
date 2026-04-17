# Example Counter Plugin

A minimal plugin example for the modular Quickshell runtime.

It demonstrates:

- Convention-based discovery (directory name = module ID)
- `Service.qml` with custom state and IPC
- `Widget.qml` that reads `context.service`
- Per-module config from `shell.json`

Enable it by adding it to [`Config/shell.json`](../../Config/shell.json):

```json
{
  "bar": {
    "right": ["example-counter"]
  },
  "modules": {
    "example-counter": {
      "enabled": true,
      "label": "ticks",
      "intervalMs": 500
    }
  }
}
```
