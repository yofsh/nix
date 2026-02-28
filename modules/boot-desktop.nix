{ config, lib, pkgs, ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.timeout = lib.mkForce 0;
  boot.plymouth.enable = true;
  boot.plymouth.theme = "bgrt";
  boot.initrd.systemd.enable = true;
  boot.consoleLogLevel = 3;
  boot.kernelParams = [ "quiet" "rd.udev.log_level=3" ];

  # Graphics
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}
