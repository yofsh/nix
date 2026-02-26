"""Preflight checks screen."""

from __future__ import annotations

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical
from textual.screen import Screen
from textual.widgets import LoadingIndicator, Static
from textual.worker import Worker, WorkerState

from ..models import PreflightResult
from ..preflight import preflight_checks


class PreflightScreen(Screen[PreflightResult | None]):
    """Runs preflight checks and displays results."""

    BINDINGS = [
        Binding("enter", "continue", "Continue", show=True),
        Binding("escape,q", "quit_screen", "Quit", show=True),
    ]

    def __init__(self, dry_run: bool) -> None:
        super().__init__()
        self.dry_run = dry_run
        self._result: PreflightResult | None = None
        self._ready = False

    def compose(self) -> ComposeResult:
        with Vertical(id="preflight-panel"):
            yield Static("Pre-flight Checks", id="title")
            yield LoadingIndicator(id="preflight-loading")
            yield Static("", id="preflight-checks")
            yield Static("[dim]enter[/dim] continue  [dim]q[/dim] quit", id="preflight-hint")

    def on_mount(self) -> None:
        self.query_one("#preflight-checks").display = False
        self.query_one("#preflight-hint").display = False
        self._run_checks()

    @work(thread=True)
    def _run_checks(self) -> PreflightResult:
        return preflight_checks(self.dry_run)

    def on_worker_state_changed(self, event: Worker.StateChanged) -> None:
        if event.worker.name == "_run_checks" and event.state == WorkerState.SUCCESS:
            result = event.worker.result
            assert isinstance(result, PreflightResult)
            self._result = result
            self._show_results(result)

    def _show_results(self, result: PreflightResult) -> None:
        self.query_one("#preflight-loading").display = False
        checks_widget = self.query_one("#preflight-checks", Static)
        checks_widget.display = True

        lines: list[str] = []
        for label, passed, fatal in result.checks:
            if passed:
                icon = "[green]\u2713[/green]"
                suffix = ""
            elif fatal:
                icon = "[red]\u2717[/red]"
                suffix = " [red](fatal)[/red]"
            else:
                icon = "[yellow]![/yellow]"
                suffix = " [yellow](warning)[/yellow]"
            lines.append(f"  {icon}  {label}{suffix}")

        if result.any_fatal:
            lines.append("")
            lines.append("[red]Fatal check(s) failed. Press q to quit.[/red]")
        else:
            self._ready = True

        checks_widget.update("\n".join(lines))
        self.query_one("#preflight-hint").display = True

    def action_continue(self) -> None:
        if self._ready:
            self.dismiss(self._result)

    def action_quit_screen(self) -> None:
        self.dismiss(None)
