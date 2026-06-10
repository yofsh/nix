# bin/ — scripts

Layout — what belongs where:

| Dir | Contents | On PATH |
|-----|----------|---------|
| `bin/` | **User commands**: anything a human types in a shell or binds to a key. Every file is executable. | everywhere |
| `bin/utils/` | **Program-called helpers**: openers/hooks/feeds invoked by yazi, imv, quickshell, Claude Code — plus session daemons (`edge-sliderd`, `hypr-watch-*`, `qs-daemon`). Never typed by the user. | everywhere |
| `bin/lib/` | **Shared code + assets**: sourced bash libs (`*.sh`), python modules (`py/*.py`), data files (`oui.db`, `sRGB.icc`). Nothing here is executable. | no |
| `bin/laptop/` | Athena-only user commands (`sensors-tui`). | interactive shell only |
| `<name>.d/` | Private modules of one multi-file command, next to that command (`yts` + `yts.d/`, `utils/qs-daemon` + `utils/qs-daemon.d/`). | — |

## Naming

- Standalone tools get **short bare names**: `ocr`, `barcode`, `upload`, `wifi`, `llm`.
- Scripts in a **domain family share a prefix**: `hypr-*` (hyprland session helpers), `cc-*` (Claude Code sessions), `bt-*` (bluetooth). A family prefix wins over `hypr-` (e.g. `cc-session-focus` is key-bound and hyprland-only, but stays `cc-*`).
- Daemons end in `d` (`edge-sliderd`) or are named `*-watch-*`/`watch`-style (`hypr-watch-monitors`).
- Sourced bash libs carry a `.sh` suffix (they are libraries, not commands); executables never do.

## Conventions

- Shebangs: `#!/usr/bin/env bash` (or `zsh`/`python3`/`bun`) — never `/bin/bash` (NixOS).
- Shared bash helpers live in `lib/` and are sourced via:
  ```bash
  LIB="$(dirname "$(readlink -f "$0")")/lib"   # from utils/: …/../lib
  . "$LIB/notify.sh"
  ```
  - `notify.sh` — `ntfy` tagged desktop toast (replaces in place; `NTFY_TAG`/`NTFY_ICON`/`NTFY_TIMEOUT` defaults)
  - `secrets.sh` — `read_secret NAME` for `/run/secrets/*`
  - `clipboard.sh` — `get_selection`, `replace_selection` (type-over with clipboard restore)
  - `capture.sh` — `grab_region` (slurp+grim JPEG; returns 1 on cancel)
  - `archive.sh` — `is_image`, `is_archive`, `extract_archive`, `find_images`
  - `print-layouts.sh` / `print-ui.sh` — photo-print rendering + interactive tuner
- Shared python helpers live in `lib/py/` and are imported via:
  ```python
  sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "lib", "py"))
  from termui import C, pad, signal_bar   # ANSI table formatting
  from oui import load_oui_db, oui_lookup # MAC-vendor lookup (lib/oui.db)
  ```
- systemd services must reference scripts by **absolute path** (services don't inherit the shell PATH) — see `home/touchpad.nix`.
- After changing hyprland-bound scripts/binds: `hyprctl reload` **and** refresh the qs-daemon keybind cache (`curl -s --unix-socket "$XDG_RUNTIME_DIR/qs-daemon.sock" http://d/keybinds/reload`).
