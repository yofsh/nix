#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/yofsh/nix.git"
CLONE_DIR="/tmp/nix-config"

# Detect if we're inside the repo (handles bash <(curl ...) where
# BASH_SOURCE resolves to /dev/fd/... or /proc/self/fd/...)
script_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" \
      && "${BASH_SOURCE[0]}" != "/dev/"* \
      && "${BASH_SOURCE[0]}" != "/proc/"* ]]; then
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# If flake.nix exists next to script, we're in the repo → run installer
if [[ -n "$script_dir" && -f "$script_dir/flake.nix" ]]; then
    quoted_args=""
    for arg in "$@"; do
        quoted_args+=" $(printf '%q' "$arg")"
    done
    exec nix-shell \
        -p "python3.withPackages (ps: [ ps.textual ])" \
        --run "cd $(printf '%q' "$script_dir") && python3 -m installer$quoted_args"
fi

# Bootstrap: clone the repo
echo "==> flake.nix not found; bootstrapping..."

run_git() {
    if command -v git &>/dev/null; then
        git "$@"
    else
        nix-shell -p git --run "git $(printf '%q ' "$@")"
    fi
}

if [[ -d "$CLONE_DIR/.git" ]]; then
    echo "==> Reusing existing clone at $CLONE_DIR"
    run_git -C "$CLONE_DIR" pull --ff-only 2>/dev/null || true
else
    echo "==> Cloning $REPO_URL..."
    rm -rf "$CLONE_DIR"
    run_git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
fi

exec bash "$CLONE_DIR/install.sh" "$@"
