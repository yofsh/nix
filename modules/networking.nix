{ config, lib, pkgs, ... }:
{
  networking.networkmanager.enable = true;
  systemd.services.NetworkManager-wait-online.enable = false;

  networking.hosts = { "192.168.1.50" = [ "srv" ]; };

  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "allow-downgrade";
      Domains = [ "~." "lan" ];
      FallbackDNS = [ "192.168.8.30" ];
      DNSOverTLS = "opportunistic";
    };
  };

  # Prefer IPv4 over IPv6 to prevent timeouts when IPv6 is unreachable
  # (fixes Claude Code and other tools hanging on API connections)
  networking.getaddrinfo.precedence = {
    "::1/128" = 50;
    "::/0" = 40;
    "2002::/16" = 30;
    "::/96" = 20;
    "::ffff:0:0/96" = 100;  # IPv4 — highest priority
  };

  # Use glibc nscd with caching instead of nsncd (non-caching)
  # nsncd forwards every NSS request without caching, causing high CPU
  # under heavy lookup patterns (npm, browsers, etc.)
  services.nscd.enableNsncd = false;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };
}
