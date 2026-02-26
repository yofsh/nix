{ config, lib, pkgs, ... }:
{
  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];
  };

  # Bambu printer LAN discovery (multicast + SSDP/mDNS ports)
  networking.firewall = {
    allowedUDPPorts = [ 1990 2021 ];
    extraCommands = ''
      iptables -I INPUT -m pkttype --pkt-type multicast -j ACCEPT
    '';
  };
}
