"""Command execution, logging, and cleanup utilities."""

from __future__ import annotations

import atexit
import os
import signal
import subprocess
import sys
from collections.abc import Callable, Iterator
from datetime import datetime
from pathlib import Path

from .exceptions import CommandError

LogFn = Callable[[str], None]

LOG_FILE = Path("/tmp/nixos-install.log")
NIX_ENV = {
    **os.environ,
    "NIX_CONFIG": "experimental-features = nix-command flakes\ndownload-buffer-size = 1073741824",
}


def log(msg: str) -> None:
    """Append a timestamped message to the log file."""
    ts = datetime.now().strftime("[%H:%M:%S]")
    with LOG_FILE.open("a") as f:
        f.write(f"{ts} {msg}\n")


def run_cmd(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = True,
    env: dict | None = None,
    dry_run: bool = False,
    dry_label: str | None = None,
    log_fn: LogFn | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run a command, log it, and raise on failure."""
    log(f"$ {' '.join(cmd)}")
    if dry_run:
        msg = f"dry-run: {dry_label or ' '.join(cmd)}"
        if log_fn:
            log_fn(msg)
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
    result = subprocess.run(
        cmd,
        capture_output=capture,
        text=True,
        env=env or NIX_ENV,
    )
    if result.stdout:
        log(result.stdout)
        if log_fn:
            for line in result.stdout.strip().splitlines():
                log_fn(line)
    if result.stderr:
        log(result.stderr)
        if log_fn:
            for line in result.stderr.strip().splitlines():
                log_fn(f"[red]{line}[/red]")
    if check and result.returncode != 0:
        raise CommandError(cmd, result.returncode, (result.stderr or "").strip()[:500])
    return result


def run_cmd_streaming(
    cmd: list[str],
    *,
    env: dict | None = None,
    dry_run: bool = False,
    dry_label: str | None = None,
) -> Iterator[str]:
    """Run a command and yield stdout+stderr lines as they arrive."""
    log(f"$ {' '.join(cmd)}")
    if dry_run:
        yield f"dry-run: {dry_label or ' '.join(cmd)}"
        return
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env or NIX_ENV,
    )
    assert proc.stdout is not None
    for line in proc.stdout:
        stripped = line.rstrip("\n")
        log(stripped)
        yield stripped
    proc.wait()
    if proc.returncode != 0:
        raise CommandError(cmd, proc.returncode)


class CleanupManager:
    def __init__(self, dry_run: bool = False) -> None:
        self._actions: list[tuple[str, list[str]]] = []
        self.dry_run = dry_run

    def register(self, label: str, cmd: list[str]) -> None:
        self._actions.append((label, cmd))

    def clear(self) -> None:
        """Remove all registered cleanup actions."""
        self._actions.clear()

    def run_all(self, log_fn: LogFn | None = None) -> None:
        for label, cmd in reversed(self._actions):
            try:
                if self.dry_run:
                    if log_fn:
                        log_fn(f"dry-run cleanup: {label}")
                else:
                    subprocess.run(cmd, capture_output=True, timeout=30)
            except Exception:
                pass
        self._actions.clear()


cleanup = CleanupManager()


def _signal_handler(_sig: int, _frame: object) -> None:
    cleanup.run_all()
    raise SystemExit(130)


signal.signal(signal.SIGINT, _signal_handler)
atexit.register(cleanup.run_all)
