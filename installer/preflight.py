"""Pre-flight safety checks."""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

from .models import PreflightResult
from .runner import NIX_ENV


def _check_root(dry_run: bool) -> tuple[str, bool]:
    passed = os.geteuid() == 0 or dry_run
    return "Running as root", passed


def _check_nixos(dry_run: bool) -> tuple[str, bool]:
    if dry_run:
        return "Running on NixOS", True
    release = Path("/etc/os-release")
    passed = release.exists() and "NixOS" in release.read_text(errors="ignore")
    return "Running on NixOS", passed


def _check_efi(dry_run: bool) -> tuple[str, bool]:
    passed = Path("/sys/firmware/efi").exists() or dry_run
    return "EFI boot mode", passed


def _check_network(dry_run: bool) -> tuple[str, bool]:
    if dry_run:
        return "Network connectivity", True
    passed = (
        subprocess.run(
            ["ping", "-c1", "-W2", "cache.nixos.org"],
            capture_output=True,
        ).returncode
        == 0
    )
    return "Network connectivity", passed


def _check_ram(dry_run: bool) -> tuple[str, bool]:
    if dry_run:
        return "RAM >= 4 GB (16.0 GB)", True
    try:
        meminfo = Path("/proc/meminfo").read_text()
        m = re.search(r"MemTotal:\s+(\d+)\s+kB", meminfo)
        ram_gb = int(m.group(1)) / 1_048_576 if m else 0
    except Exception:
        ram_gb = 0
    return f"RAM >= 4 GB ({ram_gb:.1f} GB)", ram_gb >= 4


def _check_flakes(dry_run: bool) -> tuple[str, bool]:
    if dry_run:
        return "Nix flakes enabled", True
    passed = (
        subprocess.run(
            ["nix", "flake", "--help"],
            capture_output=True,
            env=NIX_ENV,
        ).returncode
        == 0
    )
    return "Nix flakes enabled", passed


def preflight_checks(dry_run: bool) -> PreflightResult:
    """Run safety checks and return structured results."""
    checks: list[tuple[str, bool, bool]] = []

    label, passed = _check_root(dry_run)
    checks.append((label, passed, True))

    label, passed = _check_nixos(dry_run)
    checks.append((label, passed, True))

    label, passed = _check_efi(dry_run)
    checks.append((label, passed, False))

    label, passed = _check_network(dry_run)
    has_net = passed
    checks.append((label, passed, False))

    label, passed = _check_ram(dry_run)
    checks.append((label, passed, False))

    label, passed = _check_flakes(dry_run)
    checks.append((label, passed, True))

    any_fatal = any(not passed and fatal for _, passed, fatal in checks)

    return PreflightResult(checks=checks, has_net=has_net, any_fatal=any_fatal)
