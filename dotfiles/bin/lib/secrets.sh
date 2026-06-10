# shellcheck shell=bash
# secrets.sh — sops-nix secret access shared by bin/ scripts. Source, don't run.
#
#   token=$(read_secret openrouter-key) || exit 1
#
# Secrets decrypt at boot to /run/secrets/<name> (see modules/sops.nix). The
# error message lands on stderr so command substitution stays clean.

read_secret() {
  local f="/run/secrets/$1"
  if [ ! -r "$f" ]; then
    echo "${0##*/}: secret '$1' not readable at $f — add it to secrets.yaml and rebuild" >&2
    return 1
  fi
  cat "$f"
}
