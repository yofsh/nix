{ config, lib, pkgs, ... }:
{
  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];
  };

  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];
  };

  environment.systemPackages = with pkgs; [ simple-scan ];

  # Bambu printer LAN discovery (multicast + SSDP/mDNS ports)
  networking.firewall = {
    allowedUDPPorts = [ 1990 2021 ];
    extraCommands = ''
      iptables -I INPUT -m pkttype --pkt-type multicast -j ACCEPT
    '';
  };
}
