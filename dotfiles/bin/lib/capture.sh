# shellcheck shell=bash
# capture.sh — interactive screen-region capture shared by bin/ scripts (ocr,
# barcode). Source, don't run. `screenshot` keeps its own richer pipeline
# (freeze overlay, editor, upload) — this is the minimal pick-and-grab.

# grab_region OUT [quality] — slurp a region and save it as JPEG to OUT.
# Returns 1 when the selection is cancelled (caller exits silently: the user
# changed their mind, that's not an error worth a notification).
grab_region() {
  local out="$1" quality="${2:-90}" geometry
  geometry=$(slurp) || return 1
  [ -n "$geometry" ] || return 1
  grim -t jpeg -q "$quality" -g "$geometry" "$out"
}
