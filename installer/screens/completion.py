"""Completion screen — post-install summary."""

from __future__ import annotations

from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Vertical
from textual.screen import Screen
from textual.widgets import Static

from ..models import InstallConfig
from ..runner import LOG_FILE, run_cmd


class CompletionScreen(Screen[None]):
    """Shows post-installation steps and reboot option."""

    BINDINGS = [
        Binding("r", "reboot", "Reboot", show=True),
        Binding("escape,q,enter", "exit_screen", "Exit", show=True),
    ]

    def __init__(self, cfg: InstallConfig, dry_run: bool, success: bool) -> None:
        super().__init__()
        self.cfg = cfg
        self.dry_run = dry_run
        self.success = success

    def compose(self) -> ComposeResult:
        with Vertical(id="completion-panel"):
            if self.success:
                yield Static("Installation Complete!", id="title")
            else:
                yield Static("[red]Installation Failed[/red]", id="title")
            yield Static("", id="completion-steps")
            hint = "[dim]enter/q[/dim] exit"
            if self.success and not self.dry_run:
                hint = "[dim]r[/dim] reboot  " + hint
            yield Static(hint, id="completion-hint")

    def on_mount(self) -> None:
        if self.success:
            steps: list[str] = ["Remove the USB drive", "Reboot"]
            if self.cfg.encrypted:
                steps.append("Enter your LUKS password at boot")
            steps.append("On first login, home-manager will apply dotfiles automatically")
            lines = "\n".join(f"  {i}. {s}" for i, s in enumerate(steps, 1))
        else:
            tail = ""
            try:
                all_lines = LOG_FILE.read_text().splitlines()
                tail = "\n".join(all_lines[-30:])
            except Exception:
                pass
            lines = "  Check the log output for details.\n  You may re-run the installer."
            if tail:
                lines += f"\n\n[red]Last log lines:[/red]\n[dim]{tail}[/dim]"

        self.query_one("#completion-steps", Static).update(lines)

    def action_reboot(self) -> None:
        if self.success and not self.dry_run:
            run_cmd(["reboot"])

    def action_exit_screen(self) -> None:
        self.dismiss(None)
