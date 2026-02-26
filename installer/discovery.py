"""Host and disk discovery via nix eval and lsblk."""

from __future__ import annotations

import json
import re
import subprocess
import textwrap

from . import SCRIPT_DIR
from .exceptions import DiscoveryError
from .models import DiskInfo, HostInfo
from .runner import run_cmd

NIX_EVAL_EXPR = textwrap.dedent("""\
    configs: builtins.mapAttrs (name: cfg: {
      hostname = cfg.config.networking.hostName;
      isDesktop = cfg.config.programs.hyprland.enable or false;
      hasDocker = cfg.config.virtualisation.docker.enable or false;
      hasNvidia = builtins.elem "nvidia" (cfg.config.services.xserver.videoDrivers or []);
      hasFprintd = cfg.config.services.fprintd.enable or false;
      isIso = cfg.config.system.build ? isoImage;
    }) configs""")


def discover_hosts(dry_run: bool) -> list[HostInfo]:
    """Discover hosts from flake.nix via nix eval."""
    hosts: list[HostInfo] = []

    result = run_cmd(
        [
            "nix", "eval", "--json",
            f"{SCRIPT_DIR}#nixosConfigurations",
            "--apply", NIX_EVAL_EXPR,
        ],
        capture=True,
        check=False,
        dry_run=False,  # always try real eval
    )

    if result.returncode == 0 and result.stdout.strip():
        try:
            data = json.loads(result.stdout)
            for name, props in data.items():
                if props.get("isIso", False):
                    continue
                hosts.append(
                    HostInfo(
                        name=name,
                        is_desktop=props.get("isDesktop", False),
                        has_nvidia=props.get("hasNvidia", False),
                        has_docker=props.get("hasDocker", False),
                        has_fprintd=props.get("hasFprintd", False),
                        is_iso=False,
                    )
                )
        except json.JSONDecodeError:
            pass

    # Fallback: names only from flake show
    if not hosts:
        fb = run_cmd(
            ["nix", "flake", "show", "--json", str(SCRIPT_DIR)],
            capture=True,
            check=False,
        )
        if fb.returncode == 0:
            try:
                show = json.loads(fb.stdout)
                for name in show.get("nixosConfigurations", {}):
                    if name == "iso":
                        continue
                    hosts.append(HostInfo(name=name))
            except json.JSONDecodeError:
                pass

    if not hosts:
        raise DiscoveryError("Could not discover any host configurations.")

    hosts.sort(key=lambda h: h.name)
    return hosts


def _boot_device() -> str | None:
    """Return the base disk device of the current boot filesystem."""
    try:
        result = subprocess.run(
            ["findmnt", "-n", "-o", "SOURCE", "/"],
            capture_output=True,
            text=True,
        )
        src = result.stdout.strip()
        m = re.match(r"(/dev/(?:nvme\d+n\d+|sd[a-z]+|vd[a-z]+|mmcblk\d+))", src)
        return m.group(1) if m else None
    except Exception:
        return None


def discover_disks(dry_run: bool) -> list[DiskInfo]:
    """List physical disks using lsblk."""
    if dry_run:
        return [
            DiskInfo("/dev/sda", "500G", 500_000_000_000, "Fake Virtual Disk", False, False),
            DiskInfo("/dev/sdb", "1T", 1_000_000_000_000, "Fake Samsung 990 Pro", False, False),
            DiskInfo("/dev/sdc", "8G", 8_000_000_000, "Fake USB Flash", True, True),
        ]

    result = run_cmd(
        ["lsblk", "--json", "-b", "-d", "-o", "NAME,SIZE,MODEL,RM,TYPE"],
        capture=True,
    )
    data = json.loads(result.stdout)
    boot = _boot_device()
    disks: list[DiskInfo] = []
    for dev in data.get("blockdevices", []):
        if dev.get("type") != "disk":
            continue
        path = f"/dev/{dev['name']}"
        size_bytes = int(dev.get("size", 0))
        size_human = _human_size(size_bytes)
        model = (dev.get("model") or "Unknown").strip()
        removable = bool(dev.get("rm"))
        is_boot = path == boot
        disks.append(DiskInfo(path, size_human, size_bytes, model, removable, is_boot))
    return disks


def _human_size(n: int) -> str:
    for unit in ("B", "K", "M", "G", "T"):
        if n < 1024:
            return f"{n:.0f}{unit}"
        n /= 1024
    return f"{n:.0f}P"


def check_mounted(device: str) -> list[str]:
    """Return mount points for any partition on *device*."""
    try:
        result = subprocess.run(
            ["lsblk", "--json", "-o", "NAME,MOUNTPOINT", device],
            capture_output=True,
            text=True,
        )
        mounts: list[str] = []
        for dev in json.loads(result.stdout).get("blockdevices", []):
            mp = dev.get("mountpoint")
            if mp:
                mounts.append(mp)
            for child in dev.get("children", []):
                mp = child.get("mountpoint")
                if mp:
                    mounts.append(mp)
        return mounts
    except Exception:
        return []
