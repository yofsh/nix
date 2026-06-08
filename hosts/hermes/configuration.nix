{ config, lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./../../modules/base.nix
    ./../../modules/server.nix
  ];

  networking.hostName = "hermes";

  networking.firewall.allowedTCPPorts = [ 22 80 443 8123 6052 5010 5000 ];

  services.adguardhome = {
    enable = true;
    mutableSettings = true;
    port = 3001;
    settings = {
      users = [
        { name = "admin"; password = "$2y$10$3oS8DpZfae8RFYawFdXfFOl03ZjwIEh/BVBz05Z9WUAXkf.id.jau"; }
      ];
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;
        upstream_dns = [
          "[/lan/]192.168.8.1"
          "[/local/]192.168.8.1"
          "https://dns.cloudflare.com/dns-query"
          "https://dns.google/dns-query"
        ];
        bootstrap_dns = [ "1.1.1.1" "8.8.8.8" ];
        fallback_dns = [ "9.9.9.9" "1.0.0.1" ];

        ratelimit = 0;

        cache_ttl_min = 300;
        cache_ttl_max = 86400;
        cache_optimistic = true;

        upstream_timeout = "2s";
      };
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
      };
      filters = [
        { enabled = true; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"; name = "AdGuard DNS filter"; id = 1; }
        { enabled = true; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt"; name = "AdAway Default Blocklist"; id = 2; }
      ];
    };
  };

  time.timeZone = "Europe/Madrid";
}
