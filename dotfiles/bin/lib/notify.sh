# shellcheck shell=bash
# notify.sh — desktop-toast helper shared by bin/ scripts. Source, don't run.
#
#   NTFY_TAG=mytool NTFY_ICON=some-icon            # optional defaults (before or after sourcing)
#   . "$(dirname "$(readlink -f "$0")")/lib/notify.sh"
#   ntfy "Title" "Body"                            # low-urgency tagged toast
#   ntfy -u critical -i dialog-error "Failed" "x"  # later flags override the defaults
#
# The x-tag hint makes quickshell replace the previous notification carrying
# the same tag in place instead of stacking a new one. NTFY_TAG defaults to the
# calling script's name, so each tool gets one updating toast for free.

ntfy() {
  local args=(-h "string:x-tag:${NTFY_TAG:-${0##*/}}" -u low)
  [ -n "${NTFY_ICON:-}" ] && args+=(-i "$NTFY_ICON")
  [ -n "${NTFY_TIMEOUT:-}" ] && args+=(-t "$NTFY_TIMEOUT")
  notify-send "${args[@]}" "$@"
}
