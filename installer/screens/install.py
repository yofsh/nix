"""Installation progress screen."""

from __future__ import annotations

import time

from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.timer import Timer
from textual.widgets import RichLog, Static

from ..exceptions import InstallerError
from ..models import InstallConfig
from ..runner import LOG_FILE, cleanup
from ..steps import (
    cleanup_previous,
    finish,
    generate_hardware_config,
    install_nixos,
    run_disko,
    set_user_password,
    setup_user_environment,
    update_flake,
)


class _StepState:
    PENDING = "pending"
    RUNNING = "running"
    DONE = "done"
    SKIPPED = "skipped"
    FAILED = "failed"


class _StepInfo:
    def __init__(self, label: str) -> None:
        self.label = label
        self.state = _StepState.PENDING
        self.elapsed: float | None = None
        self._start: float | None = None

    def start(self) -> None:
        self.state = _StepState.RUNNING
        self._start = time.monotonic()

    def done(self) -> None:
        self.state = _StepState.DONE
        if self._start is not None:
            self.elapsed = time.monotonic() - self._start

    def skip(self) -> None:
        self.state = _StepState.SKIPPED

    def fail(self) -> None:
        self.state = _StepState.FAILED
        if self._start is not None:
            self.elapsed = time.monotonic() - self._start

    @property
    def running_elapsed(self) -> float:
        if self._start is not None and self.state == _StepState.RUNNING:
            return time.monotonic() - self._start
        return 0.0


_ICONS = {
    _StepState.PENDING: ("\u25cb", "dim"),
    _StepState.RUNNING: ("\u25d0", "blue"),
    _StepState.DONE: ("\u25cf", "green"),
    _StepState.SKIPPED: ("\u25cb", "yellow"),
    _StepState.FAILED: ("\u2717", "red"),
}


class InstallScreen(Screen[bool]):
    """Runs installation steps with live log output."""

    def __init__(self, cfg: InstallConfig, dry_run: bool, has_net: bool) -> None:
        super().__init__()
        self.cfg = cfg
        self.dry_run = dry_run
        self.has_net = has_net
        self._timer: Timer | None = None
        self._step_infos: list[_StepInfo] = [
            _StepInfo("Cleanup previous"),
            _StepInfo("Update flake"),
            _StepInfo("Partition disk"),
            _StepInfo("Hardware config"),
            _StepInfo("Install NixOS"),
            _StepInfo("Set password"),
            _StepInfo("Setup environment"),
            _StepInfo("Finalize"),
        ]

    def compose(self) -> ComposeResult:
        with Horizontal():
            with Vertical(id="install-sidebar"):
                yield Static("Steps", id="sidebar-title")
                yield Static("", id="install-steps")
            with Vertical(id="install-log-container"):
                title = "Output"
                if self.dry_run:
                    title += " [yellow](DRY RUN)[/yellow]"
                yield Static(title, id="log-title")
                yield RichLog(highlight=True, markup=True, wrap=True, id="install-log")

    def on_mount(self) -> None:
        LOG_FILE.write_text("")
        cleanup.dry_run = self.dry_run
        self._update_checklist()
        self._timer = self.set_interval(1.0, self._update_checklist)
        self._run_installation()

    def _update_checklist(self) -> None:
        lines: list[str] = []
        for info in self._step_infos:
            icon, style = _ICONS[info.state]
            if info.state == _StepState.RUNNING:
                elapsed_str = f"{info.running_elapsed:.0f}s"
            elif info.elapsed is not None:
                elapsed_str = f"{info.elapsed:.0f}s"
            else:
                elapsed_str = ""
            lines.append(f"  [{style}]{icon} {info.label:<18} {elapsed_str}[/{style}]")
        self.query_one("#install-steps", Static).update("\n".join(lines))

    def _log_write(self, text: str) -> None:
        """Thread-safe log writer."""
        self.app.call_from_thread(self._write_to_log, text)

    def _write_to_log(self, text: str) -> None:
        try:
            self.query_one("#install-log", RichLog).write(text)
        except Exception:
            pass

    @work(thread=True)
    def _run_installation(self) -> None:
        assert self.cfg.host and self.cfg.disk
        success = False

        try:
            # Step 0: Cleanup previous
            self._step_infos[0].start()
            self.app.call_from_thread(self._update_checklist)
            cleanup_previous(self.dry_run, log_fn=self._log_write)
            self._step_infos[0].done()
            self.app.call_from_thread(self._update_checklist)

            # Step 1: Update flake
            if self.cfg.update_flake:
                self._step_infos[1].start()
                self.app.call_from_thread(self._update_checklist)
                for line in update_flake(self.dry_run):
                    self._log_write(line)
                self._step_infos[1].done()
            else:
                self._step_infos[1].skip()
            self.app.call_from_thread(self._update_checklist)

            # Step 2: Partition disk
            self._step_infos[2].start()
            self.app.call_from_thread(self._update_checklist)
            for line in run_disko(self.cfg, self.dry_run, log_fn=self._log_write):
                self._log_write(line)
            self._step_infos[2].done()
            self.app.call_from_thread(self._update_checklist)

            # Step 3: Generate hardware config
            self._step_infos[3].start()
            self.app.call_from_thread(self._update_checklist)
            generate_hardware_config(self.cfg.host.name, self.dry_run, log_fn=self._log_write)
            self._step_infos[3].done()
            self.app.call_from_thread(self._update_checklist)

            # Step 4: Install NixOS
            self._step_infos[4].start()
            self.app.call_from_thread(self._update_checklist)
            for line in install_nixos(self.cfg.host.name, self.dry_run):
                self._log_write(line)
            self._step_infos[4].done()
            self.app.call_from_thread(self._update_checklist)

            # Step 5: Set user password
            self._step_infos[5].start()
            self.app.call_from_thread(self._update_checklist)
            set_user_password(self.cfg, self.dry_run, log_fn=self._log_write)
            self._step_infos[5].done()
            self.app.call_from_thread(self._update_checklist)

            # Step 6: Setup user environment
            self._step_infos[6].start()
            self.app.call_from_thread(self._update_checklist)
            setup_user_environment(self.cfg, self.dry_run, self.has_net, log_fn=self._log_write)
            self._step_infos[6].done()
            self.app.call_from_thread(self._update_checklist)

            # Step 7: Finalize
            self._step_infos[7].start()
            self.app.call_from_thread(self._update_checklist)
            finish(self.cfg, self.dry_run, log_fn=self._log_write)
            self._step_infos[7].done()
            self.app.call_from_thread(self._update_checklist)

            success = True

        except InstallerError as e:
            self._log_write(f"[red]Error: {e}[/red]")
            for info in self._step_infos:
                if info.state == _StepState.RUNNING:
                    info.fail()
            self.app.call_from_thread(self._update_checklist)

        except Exception as e:
            self._log_write(f"[red]Unexpected error: {e}[/red]")
            for info in self._step_infos:
                if info.state == _StepState.RUNNING:
                    info.fail()
            self.app.call_from_thread(self._update_checklist)

        finally:
            if self._timer:
                self.app.call_from_thread(self._timer.stop)
            self.app.call_from_thread(self._update_checklist)
            self.app.call_from_thread(self.dismiss, success)
