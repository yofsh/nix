"""Data models for the NixOS installer."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class HostInfo:
    name: str
    is_desktop: bool = False
    has_nvidia: bool = False
    has_docker: bool = False
    has_fprintd: bool = False
    is_iso: bool = False

    @property
    def description(self) -> str:
        role = "Desktop" if self.is_desktop else "Server"
        tags: list[str] = []
        if self.has_nvidia:
            tags.append("NVIDIA GPU")
        if self.has_docker:
            tags.append("Docker")
        if self.has_fprintd:
            tags.append("Fingerprint")
        suffix = f" | {', '.join(tags)}" if tags else ""
        return f"{role}{suffix}"


@dataclass
class DiskInfo:
    device: str
    size_human: str
    size_bytes: int
    model: str
    is_removable: bool
    is_boot_disk: bool


@dataclass
class InstallConfig:
    host: HostInfo | None = None
    disk: DiskInfo | None = None
    disk2: DiskInfo | None = None
    dual_disk: bool = False
    encrypted: bool = False
    luks_password: str | None = None
    user_password: str | None = None
    update_flake: bool = False
    user: str = "fobos"


@dataclass
class PreflightResult:
    checks: list[tuple[str, bool, bool]] = field(default_factory=list)
    has_net: bool = False
    any_fatal: bool = False
