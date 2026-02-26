"""Textual application for the NixOS installer."""

from __future__ import annotations

from textual.app import App

from .models import InstallConfig, PreflightResult
from .screens import CompletionScreen, InstallScreen, PreflightScreen, WizardScreen


class InstallerApp(App[None]):
    CSS_PATH = "installer.tcss"
    TITLE = "NixOS Flake Installer"

    def __init__(self, dry_run: bool) -> None:
        super().__init__()
        self.dry_run = dry_run
        self._has_net = False
        self._cfg: InstallConfig | None = None

    def on_mount(self) -> None:
        self.push_screen(PreflightScreen(self.dry_run), callback=self._on_preflight_done)

    def _on_preflight_done(self, result: PreflightResult | None) -> None:
        if result is None:
            self.exit()
            return
        self._has_net = result.has_net
        self.push_screen(
            WizardScreen(self.dry_run, self._has_net),
            callback=self._on_wizard_done,
        )

    def _on_wizard_done(self, cfg: InstallConfig | None) -> None:
        if cfg is None:
            self.exit()
            return
        self._cfg = cfg
        self.push_screen(
            InstallScreen(cfg, self.dry_run, self._has_net),
            callback=self._on_install_done,
        )

    def _on_install_done(self, success: bool) -> None:
        assert self._cfg is not None
        self.push_screen(
            CompletionScreen(self._cfg, self.dry_run, success),
            callback=self._on_completion_done,
        )

    def _on_completion_done(self, _result: None) -> None:
        self.exit()
