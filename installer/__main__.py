"""NixOS Flake Installer — entry point.

Usage: sudo python3 -m installer [--dry-run]
"""

from __future__ import annotations

import argparse

from .app import InstallerApp


def main() -> None:
    parser = argparse.ArgumentParser(description="NixOS Flake Installer")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would happen without making changes",
    )
    args = parser.parse_args()
    InstallerApp(dry_run=args.dry_run).run()


if __name__ == "__main__":
    main()
