{ config, lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./../../modules/base.nix
    ./../../modules/server.nix
  ];

  networking.hostName = "demeter";

  networking.firewall.allowedTCPPorts = [ 22 19999 ];

  time.timeZone = "Europe/Kyiv";

  services.netdata = {
    enable = true;
  };

  hardware.coral.pcie.enable = true;
}
