# shellcheck shell=bash
# clipboard.sh — Wayland selection helpers shared by bin/ scripts. Source, don't run.

# get_selection — print the text currently selected in the focused window.
# Simulates the app's copy shortcut (terminals need Ctrl+Shift+C) and polls the
# clipboard for the result, then restores whatever the clipboard held before.
# Works in apps that don't publish the primary selection (e.g. some browsers).
get_selection() {
  local saved text="" cls
  saved=$(wl-paste 2>/dev/null)        # back up real clipboard
  wl-copy --clear                      # sentinel to detect when the copy lands

  cls=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')
  case "$cls" in
    foot|footclient) wtype -M ctrl -M shift c ;;   # terminal: Ctrl+Shift+C
    *)               wtype -M ctrl c ;;            # everything else: Ctrl+C
  esac

  for _ in $(seq 1 20); do             # poll up to ~1s for the app to fill the clipboard
    text=$(wl-paste --no-newline 2>/dev/null)
    [ -n "$text" ] && break
    sleep 0.05
  done

  printf '%s' "$saved" | wl-copy       # restore real clipboard
  printf '%s' "$text"
}

# replace_selection REPLACEMENT ORIGINAL — type REPLACEMENT over the current
# selection via a simulated paste, then put ORIGINAL back on the clipboard so
# the user's clipboard survives the round-trip.
replace_selection() {
  local replacement="$1" original="$2"
  wl-copy "$replacement"
  wtype -M ctrl v
  sleep 0.5                            # let the app consume the paste first
  wl-copy "$original"
}
