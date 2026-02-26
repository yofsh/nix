"""Installer exception hierarchy."""

from __future__ import annotations


class InstallerError(Exception):
    """Base exception for all installer errors."""


class CommandError(InstallerError):
    """A subprocess exited with a non-zero return code."""

    def __init__(self, cmd: list[str], returncode: int, stderr: str = "") -> None:
        self.cmd = cmd
        self.returncode = returncode
        self.stderr = stderr
        super().__init__(f"Command failed (rc={returncode}): {' '.join(cmd)}")


class DiscoveryError(InstallerError):
    """Host or disk discovery failed."""


class StepError(InstallerError):
    """An installation step failed."""
