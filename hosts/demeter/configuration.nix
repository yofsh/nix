{ config, lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./../../modules/base.nix
    ./../../modules/server.nix
  ];

  networking.hostName = "demeter";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 19999 ];
  };

  time.timeZone = "Europe/Kyiv";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "24.05";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  services.netdata = {
    enable = true;
  };

  hardware.coral.pcie.enable = true;
}
