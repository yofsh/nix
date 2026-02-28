{ config, lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.timeout = lib.mkForce 0;
  boot.plymouth.enable = true;
  boot.plymouth.theme = "bgrt";
  boot.initrd.systemd.enable = true;
  boot.consoleLogLevel = 0;
  boot.kernelParams = [ "quiet" "splash" "loglevel=0" "vt.global_cursor_default=0" ];

  # Graphics
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
