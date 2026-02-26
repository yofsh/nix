"""Wizard screen — multi-step configuration flow."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from textual import work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.screen import Screen
from textual.widgets import DataTable, Input, OptionList, Static
from textual.widgets.option_list import Option
from textual.worker import Worker, WorkerState

from ..discovery import discover_disks, discover_hosts
from ..models import DiskInfo, HostInfo, InstallConfig


@dataclass
class WizardStep:
    key: str
    label: str
    value: str = ""
    enabled: bool = True
    data: Any = None


class WizardScreen(Screen[InstallConfig | None]):
    """Multi-step wizard for installation configuration."""

    BINDINGS = [
        Binding("escape", "go_back", "Back", show=True),
        Binding("q", "quit_screen", "Quit", show=True),
    ]

    def __init__(self, dry_run: bool, has_net: bool) -> None:
        super().__init__()
        self.dry_run = dry_run
        self.has_net = has_net
        self._hosts: list[HostInfo] = []
        self._disks: list[DiskInfo] = []
        self._current_step = 0
        self._steps: list[WizardStep] = [
            WizardStep(key="host", label="Host"),
            WizardStep(key="encrypt", label="Encryption"),
            WizardStep(key="layout", label="Layout"),
            WizardStep(key="disk1", label="Disk"),
            WizardStep(key="disk2", label="Disk 2", enabled=False),
            WizardStep(key="password", label="Password"),
            WizardStep(key="flake", label="Flake update", enabled=self.has_net),
            WizardStep(key="confirm", label="Confirm"),
        ]

    def compose(self) -> ComposeResult:
        with Horizontal(id="wizard-body"):
            with Vertical(id="wizard-sidebar"):
                yield Static("Steps", id="sidebar-title")
                yield Static("", id="sidebar-steps")
            with VerticalScroll(id="wizard-content"):
                yield Static("Loading...", id="content-title")

    def on_mount(self) -> None:
        self._discover()

    @work(thread=True)
    def _discover(self) -> tuple[list[HostInfo], list[DiskInfo]]:
        hosts = discover_hosts(self.dry_run)
        disks = discover_disks(self.dry_run)
        return hosts, disks

    def on_worker_state_changed(self, event: Worker.StateChanged) -> None:
        if event.worker.name == "_discover" and event.state == WorkerState.SUCCESS:
            hosts, disks = event.worker.result
            self._hosts = hosts
            self._disks = disks
            self._show_step()
        elif event.worker.name == "_discover" and event.state == WorkerState.ERROR:
            title = self.query_one("#content-title", Static)
            title.update("[red]Discovery failed. Check your flake configuration.[/red]")

    def _enabled_steps(self) -> list[WizardStep]:
        return [s for s in self._steps if s.enabled]

    def _current(self) -> WizardStep:
        return self._enabled_steps()[self._current_step]

    def _update_sidebar(self) -> None:
        enabled = self._enabled_steps()
        lines: list[str] = []
        for i, step in enumerate(enabled):
            if i < self._current_step:
                icon = "[green]\u2713[/green]"
                val = f"  [dim]{step.value}[/dim]" if step.value else ""
            elif i == self._current_step:
                icon = "[blue]>[/blue]"
                val = ""
            else:
                icon = "[dim]\u25cb[/dim]"
                val = ""
            lines.append(f"  {icon} {step.label}{val}")

        hint = "\n\n[dim]enter[/dim] select  [dim]esc[/dim] back  [dim]q[/dim] quit"
        self.query_one("#sidebar-steps", Static).update("\n".join(lines) + hint)

    def _show_step(self) -> None:
        self._update_sidebar()
        step = self._current()
        content = self.query_one("#wizard-content", VerticalScroll)

        # Remove old step widgets (keep the title)
        for child in list(content.children):
            if child.id != "content-title":
                child.remove()

        title = self.query_one("#content-title", Static)

        if step.key == "host":
            title.update("Select Host")
            options = [Option(f"{h.name:<12} {h.description}", id=h.name) for h in self._hosts]
            ol = OptionList(*options, id="host-list")
            content.mount(ol)
            if step.data is not None:
                for i, h in enumerate(self._hosts):
                    if h.name == step.data.name:
                        ol.highlighted = i
                        break
            self.call_later(ol.focus)

        elif step.key == "encrypt":
            title.update("Disk Encryption")
            options = [
                Option("LUKS Encrypted (recommended)", id="luks"),
                Option("No encryption", id="none"),
            ]
            ol = OptionList(*options, id="encrypt-list")
            content.mount(ol)
            if step.data is not None:
                ol.highlighted = 0 if step.data else 1
            self.call_later(ol.focus)

        elif step.key == "layout":
            title.update("Disk Layout")
            options = [
                Option("Single disk", id="single"),
                Option("Dual disk (btrfs RAID0)", id="dual"),
            ]
            ol = OptionList(*options, id="layout-list")
            content.mount(ol)
            if step.data is not None:
                ol.highlighted = 1 if step.data else 0
            self.call_later(ol.focus)

        elif step.key == "disk1":
            title.update("Select Disk")
            dt = self._make_disk_table("disk1-table", exclude=None)
            content.mount(dt)
            self.call_later(dt.focus)

        elif step.key == "disk2":
            title.update("Select Second Disk (RAID0)")
            disk1_step = next(s for s in self._steps if s.key == "disk1")
            exclude = disk1_step.data.device if disk1_step.data else None
            dt = self._make_disk_table("disk2-table", exclude=exclude)
            content.mount(dt)
            self.call_later(dt.focus)

        elif step.key == "password":
            title.update("Set User Password [dim](tab to switch, enter to confirm)[/dim]")
            container = Vertical(id="password-container")
            content.mount(container)
            pw1 = Input(placeholder="Password", password=True, id="pw1")
            container.mount(Static("You will need this password to log in."))
            container.mount(pw1)
            container.mount(Input(placeholder="Confirm password", password=True, id="pw2"))
            container.mount(Static("", id="password-validation"))
            if step.data:
                self.call_later(self._restore_password, step.data)
            self.call_later(pw1.focus)

        elif step.key == "flake":
            title.update("Update Flake")
            options = [
                Option("Yes \u2014 update flake.lock to latest", id="yes"),
                Option("No \u2014 keep current lockfile", id="no"),
            ]
            ol = OptionList(*options, id="flake-list")
            content.mount(ol)
            if step.data is not None:
                ol.highlighted = 0 if step.data else 1
            self.call_later(ol.focus)

        elif step.key == "confirm":
            title.update("Confirm Installation [dim](enter to install)[/dim]")
            summary = self._build_summary()
            content.mount(Static(summary, id="confirm-summary"))

    def _restore_password(self, pw: str) -> None:
        try:
            self.query_one("#pw1", Input).value = pw
            self.query_one("#pw2", Input).value = pw
        except Exception:
            pass

    def _make_disk_table(self, table_id: str, exclude: str | None) -> DataTable:
        dt = DataTable(id=table_id, cursor_type="row")
        dt.add_columns("Device", "Size", "Model", "Notes")
        disks = [d for d in self._disks if d.device != exclude] if exclude else self._disks
        for d in disks:
            notes_parts: list[str] = []
            if d.is_boot_disk:
                notes_parts.append("boot disk")
            if d.is_removable:
                notes_parts.append("removable")
            dt.add_row(d.device, d.size_human, d.model, " ".join(notes_parts), key=d.device)
        return dt

    def _build_summary(self) -> str:
        lines: list[str] = []
        for step in self._enabled_steps():
            if step.key == "confirm":
                continue
            lines.append(f"  {step.label:<14} {step.value}")

        text = "\n".join(lines)
        if not self.dry_run:
            text += "\n\n[bold red]WARNING: This will destroy all data on the selected disk(s)![/bold red]"
        return text

    def _advance(self) -> None:
        """Capture current selection and move to next step."""
        if not self._select_current():
            return
        enabled = self._enabled_steps()
        if self._current_step < len(enabled) - 1:
            self._current_step += 1
            self._show_step()

    def _select_current(self) -> bool:
        """Capture the current step's selection. Returns False if validation fails."""
        step = self._current()

        if step.key == "host":
            try:
                ol = self.query_one("#host-list", OptionList)
            except Exception:
                return False
            if ol.highlighted is None:
                return False
            host = self._hosts[ol.highlighted]
            step.data = host
            step.value = host.name

        elif step.key == "encrypt":
            try:
                ol = self.query_one("#encrypt-list", OptionList)
            except Exception:
                return False
            if ol.highlighted is None:
                return False
            encrypted = ol.highlighted == 0
            step.data = encrypted
            step.value = "LUKS" if encrypted else "None"

        elif step.key == "layout":
            try:
                ol = self.query_one("#layout-list", OptionList)
            except Exception:
                return False
            if ol.highlighted is None:
                return False
            dual = ol.highlighted == 1
            step.data = dual
            step.value = "Dual RAID0" if dual else "Single"
            disk2_step = next(s for s in self._steps if s.key == "disk2")
            disk2_step.enabled = dual
            if not dual:
                disk2_step.data = None
                disk2_step.value = ""

        elif step.key == "disk1":
            disk = self._get_selected_disk("disk1-table", None)
            if disk is None:
                return False
            if disk.is_boot_disk:
                self._show_disk_error("Cannot install to the current boot disk.")
                return False
            step.data = disk
            step.value = f"{disk.device} ({disk.size_human})"

        elif step.key == "disk2":
            disk1 = next(s for s in self._steps if s.key == "disk1").data
            exclude = disk1.device if disk1 else None
            disk = self._get_selected_disk("disk2-table", exclude)
            if disk is None:
                return False
            if disk.is_boot_disk:
                self._show_disk_error("Cannot use the current boot disk.")
                return False
            step.data = disk
            step.value = f"{disk.device} ({disk.size_human})"

        elif step.key == "password":
            try:
                pw1 = self.query_one("#pw1", Input).value
                pw2 = self.query_one("#pw2", Input).value
            except Exception:
                return False
            if not pw1:
                self._show_password_error("Password cannot be empty.")
                return False
            if pw1 != pw2:
                self._show_password_error("Passwords do not match.")
                return False
            step.data = pw1
            step.value = "***"

        elif step.key == "flake":
            try:
                ol = self.query_one("#flake-list", OptionList)
            except Exception:
                return False
            if ol.highlighted is None:
                return False
            update = ol.highlighted == 0
            step.data = update
            step.value = "Yes" if update else "No"

        elif step.key == "confirm":
            cfg = self._build_config()
            self.dismiss(cfg)
            return True

        return True

    def _get_selected_disk(self, table_id: str, exclude: str | None) -> DiskInfo | None:
        try:
            dt = self.query_one(f"#{table_id}", DataTable)
        except Exception:
            return None
        if dt.cursor_row is None:
            return None
        disks = [d for d in self._disks if d.device != exclude] if exclude else self._disks
        if 0 <= dt.cursor_row < len(disks):
            return disks[dt.cursor_row]
        return None

    def _show_disk_error(self, msg: str) -> None:
        title = self.query_one("#content-title", Static)
        title.update(f"[red]{msg}[/red]")

    def _show_password_error(self, msg: str) -> None:
        try:
            self.query_one("#password-validation", Static).update(f"[red]{msg}[/red]")
        except Exception:
            pass

    def _build_config(self) -> InstallConfig:
        steps = {s.key: s for s in self._steps}
        cfg = InstallConfig()
        cfg.host = steps["host"].data
        cfg.encrypted = steps["encrypt"].data or False
        cfg.dual_disk = steps["layout"].data or False
        cfg.disk = steps["disk1"].data
        if cfg.dual_disk and steps["disk2"].data:
            cfg.disk2 = steps["disk2"].data
        cfg.user_password = steps["password"].data
        if cfg.encrypted:
            cfg.luks_password = steps["password"].data
        cfg.update_flake = steps["flake"].data if steps["flake"].enabled else False
        return cfg

    def action_go_back(self) -> None:
        if self._current_step > 0:
            self._current_step -= 1
            self._show_step()

    def action_quit_screen(self) -> None:
        self.dismiss(None)

    def on_option_list_option_selected(self, event: OptionList.OptionSelected) -> None:
        """Enter on an OptionList item → advance."""
        self._advance()

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        """Enter on a DataTable row → advance."""
        self._advance()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        """Enter in password input → try to advance."""
        step = self._current()
        if step.key == "password":
            # If in pw1, move focus to pw2; if in pw2, try to advance
            if event.input.id == "pw1":
                try:
                    self.query_one("#pw2", Input).focus()
                except Exception:
                    pass
            elif event.input.id == "pw2":
                self._advance()

    def key_enter(self) -> None:
        """Enter on confirm step (no focusable widget) → advance."""
        step = self._current()
        if step.key == "confirm":
            self._advance()
