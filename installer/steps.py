"""Installation step functions."""

from __future__ import annotations

import shutil
import subprocess
import textwrap
from collections.abc import Iterator
from pathlib import Path

from . import SCRIPT_DIR
from .exceptions import StepError
from .models import InstallConfig
from .runner import LogFn, cleanup, run_cmd, run_cmd_streaming

REPO_HTTPS = "https://github.com/yofsh/nix.git"
REPO_SSH = "git@github.com:yofsh/nix.git"

DISKO_DIR = SCRIPT_DIR / "disko"
DISKO_PLACEHOLDER = "REPLACE_ME"
DISKO_PLACEHOLDER_1 = "REPLACE_ME_1"
DISKO_PLACEHOLDER_2 = "REPLACE_ME_2"
DISKO_PLACEHOLDER_2_PART = "REPLACE_ME_2_PART"


def _partition_path(device: str, part_num: int = 1) -> str:
    """Compute partition device path (e.g., /dev/sda -> /dev/sda1, /dev/nvme0n1 -> /dev/nvme0n1p1)."""
    if "nvme" in device or "mmcblk" in device or "loop" in device:
        return f"{device}p{part_num}"
    return f"{device}{part_num}"


def cleanup_previous(dry_run: bool, log_fn: LogFn | None = None) -> None:
    """Clean up mounts/swap from a previous failed run."""
    if log_fn:
        log_fn("Cleaning up from previous run...")
    for cmd in (
        ["swapoff", "/mnt/swapfile"],
        ["rm", "-f", "/mnt/swapfile"],
        ["umount", "-R", "/mnt"],
        ["cryptsetup", "close", "crypted"],
    ):
        run_cmd(cmd, check=False, capture=True, dry_run=dry_run, dry_label=" ".join(cmd), log_fn=log_fn)
    if log_fn:
        log_fn("Cleanup done.")


def update_flake(dry_run: bool) -> Iterator[str]:
    """Update flake.lock to latest packages."""
    yield from run_cmd_streaming(
        ["nix", "flake", "update", "--flake", str(SCRIPT_DIR)],
        dry_run=dry_run,
        dry_label="nix flake update",
    )


def prepare_disko_config(cfg: InstallConfig) -> Path:
    """Copy the appropriate disko config to /tmp and substitute the device(s)."""
    assert cfg.disk
    tmp_dir = Path("/tmp/disko-install")
    tmp_dir.mkdir(exist_ok=True)

    # Copy common.nix alongside the config so the import works
    shutil.copy2(DISKO_DIR / "common.nix", tmp_dir / "common.nix")

    if cfg.dual_disk and cfg.disk2:
        source = DISKO_DIR / "dual.nix"
        content = source.read_text()
        content = content.replace(DISKO_PLACEHOLDER_1, cfg.disk.device)
        # Replace _2_PART before _2 to avoid partial match
        content = content.replace(DISKO_PLACEHOLDER_2_PART, _partition_path(cfg.disk2.device))
        content = content.replace(DISKO_PLACEHOLDER_2, cfg.disk2.device)
    else:
        source = DISKO_DIR / ("luks.nix" if cfg.encrypted else "default.nix")
        content = source.read_text()
        content = content.replace(DISKO_PLACEHOLDER, cfg.disk.device)

    dest = tmp_dir / "config.nix"
    dest.write_text(content)

    return dest


def run_disko(cfg: InstallConfig, dry_run: bool, log_fn: LogFn | None = None) -> Iterator[str]:
    """Partition and format the target disk."""
    assert cfg.disk
    disk = cfg.disk.device

    # Write LUKS key if encrypted
    if cfg.encrypted and cfg.luks_password:
        secret = Path("/tmp/secret.key")
        secret.write_text(cfg.luks_password)
        secret.chmod(0o600)
        cleanup.register("remove secret key", ["rm", "-f", "/tmp/secret.key"])

    disko_path = prepare_disko_config(cfg)
    cleanup.register("remove disko config", ["rm", "-rf", "/tmp/disko-install"])

    yield from run_cmd_streaming(
        ["nix", "run", "github:nix-community/disko", "--", "--mode", "disko", str(disko_path)],
        dry_run=dry_run,
        dry_label=f"disko {disk}",
    )

    if not dry_run:
        result = run_cmd(["findmnt", "--target", "/mnt"], capture=True, check=False)
        if result.stdout and log_fn:
            log_fn(result.stdout.strip())

    # Temp swap for large installs
    if not dry_run:
        run_cmd(["dd", "if=/dev/zero", "of=/mnt/swapfile", "bs=1M", "count=8192", "status=progress"], log_fn=log_fn)
        run_cmd(["chmod", "600", "/mnt/swapfile"], log_fn=log_fn)
        run_cmd(["mkswap", "/mnt/swapfile"], log_fn=log_fn)
        run_cmd(["swapon", "/mnt/swapfile"], log_fn=log_fn)
        cleanup.register("swapoff", ["swapoff", "/mnt/swapfile"])
        cleanup.register("remove swapfile", ["rm", "-f", "/mnt/swapfile"])
    elif log_fn:
        log_fn("dry-run: create 8G swap")

    # Expand tmpfs
    run_cmd(
        ["mount", "-o", "remount,size=16G", "/nix/.rw-store"],
        dry_run=dry_run,
        dry_label="expand /nix/.rw-store to 16G",
        log_fn=log_fn,
    )


def generate_hardware_config(host: str, dry_run: bool, log_fn: LogFn | None = None) -> None:
    """Generate hardware-configuration.nix for the target host."""
    host_dir = SCRIPT_DIR / "hosts" / host
    host_dir.mkdir(parents=True, exist_ok=True)

    if dry_run:
        if log_fn:
            log_fn("dry-run: nixos-generate-config")
    else:
        tmp = Path("/tmp/nixos-config")
        run_cmd(["nixos-generate-config", "--root", "/mnt", "--dir", str(tmp)], log_fn=log_fn)
        hw_src = tmp / "hardware-configuration.nix"
        hw_dst = host_dir / "hardware-configuration.nix"
        hw_dst.write_text(hw_src.read_text())
        run_cmd(["rm", "-rf", str(tmp)], check=False, log_fn=log_fn)
        if log_fn:
            log_fn(f"Generated {hw_dst}")


def install_nixos(host: str, dry_run: bool) -> Iterator[str]:
    """Run nixos-install for the target host."""
    yield from run_cmd_streaming(
        [
            "nixos-install",
            "--flake", f"{SCRIPT_DIR}#{host}",
            "--no-root-passwd",
            "--option", "keep-outputs", "false",
        ],
        dry_run=dry_run,
        dry_label=f"nixos-install --flake .#{host}",
    )


def set_user_password(cfg: InstallConfig, dry_run: bool, log_fn: LogFn | None = None) -> None:
    """Set the user password on the installed system."""
    password = cfg.user_password or cfg.luks_password
    if not password:
        if dry_run:
            password = "dry-run-password"
        else:
            raise StepError("No password available for user account.")

    if dry_run:
        if log_fn:
            log_fn("dry-run: set user password")
    else:
        proc = subprocess.run(
            ["nixos-enter", "--root", "/mnt", "--", "chpasswd"],
            input=f"{cfg.user}:{password}",
            text=True,
            capture_output=True,
        )
        if proc.returncode != 0:
            raise StepError(f"Failed to set password: {proc.stderr.strip()}")
        if log_fn:
            log_fn("User password set.")


def setup_user_environment(cfg: InstallConfig, dry_run: bool, has_net: bool, log_fn: LogFn | None = None) -> None:
    """Copy nix repo and create first-login script."""
    target = Path(f"/mnt/home/{cfg.user}/nix")
    has_git = (SCRIPT_DIR / ".git").is_dir()

    if has_git:
        if log_fn:
            log_fn(f"Copying nix repo (with .git) to /home/{cfg.user}/nix...")
        if not dry_run:
            run_cmd(["cp", "-a", str(SCRIPT_DIR), str(target)], log_fn=log_fn)
            run_cmd(
                ["git", "-C", str(target), "remote", "set-url", "origin", REPO_SSH],
                check=False,
                log_fn=log_fn,
            )
    elif has_net:
        if log_fn:
            log_fn("Cloning yofsh/nix from GitHub...")
        if not dry_run:
            run_cmd(["git", "clone", REPO_HTTPS, str(target)], log_fn=log_fn)
    else:
        if log_fn:
            log_fn("No .git and no network -- copying snapshot.")
        if not dry_run:
            run_cmd(["cp", "-a", str(SCRIPT_DIR), str(target)], log_fn=log_fn)

    if dry_run:
        method = "copy with .git" if has_git else ("git clone" if has_net else "copy snapshot")
        if log_fn:
            log_fn(f"dry-run: {method} to /mnt/home/{cfg.user}/nix")
    else:
        run_cmd(["chown", "-R", "1000:100", str(target)], log_fn=log_fn)

    # First-login script
    if log_fn:
        log_fn("Creating first-login setup script...")
    first_login = textwrap.dedent(f"""\
        #!/usr/bin/env bash
        echo "Applying home-manager configuration..."
        cd ~/nix && home-manager switch --flake .#{cfg.user}
        if [ $? -eq 0 ]; then
            echo "Home-manager applied successfully!"
            rm -f ~/.first-login.sh
            sed -i '/\\.first-login\\.sh/d' ~/.bash_profile ~/.zprofile 2>/dev/null
        else
            echo "Home-manager failed. Run manually: cd ~/nix && home-manager switch --flake .#{cfg.user}"
        fi
    """)

    if not dry_run:
        fl_path = Path(f"/mnt/home/{cfg.user}/.first-login.sh")
        fl_path.write_text(first_login)
        fl_path.chmod(0o755)

        profile_line = '[ -f ~/.first-login.sh ] && ~/.first-login.sh\n'
        for name in (".bash_profile", ".zprofile"):
            p = Path(f"/mnt/home/{cfg.user}/{name}")
            existing = p.read_text() if p.exists() else ""
            p.write_text(existing + profile_line)

        for f in (fl_path, Path(f"/mnt/home/{cfg.user}/.bash_profile"), Path(f"/mnt/home/{cfg.user}/.zprofile")):
            run_cmd(["chown", "1000:100", str(f)], log_fn=log_fn)
        if log_fn:
            log_fn("First-login script created.")
    elif log_fn:
        log_fn("dry-run: create first-login script")


def finish(cfg: InstallConfig, dry_run: bool, log_fn: LogFn | None = None) -> None:
    """Clean up temp files, swap, and mounts."""
    Path("/tmp/secret.key").unlink(missing_ok=True)
    shutil.rmtree("/tmp/disko-install", ignore_errors=True)

    run_cmd(["swapoff", "/mnt/swapfile"], check=False, capture=True, dry_run=dry_run, log_fn=log_fn)
    run_cmd(["rm", "-f", "/mnt/swapfile"], check=False, capture=True, dry_run=dry_run, log_fn=log_fn)
    run_cmd(["umount", "-R", "/mnt"], check=False, capture=True, dry_run=dry_run, log_fn=log_fn)

    cleanup.clear()
    if log_fn:
        log_fn("Cleanup complete.")
