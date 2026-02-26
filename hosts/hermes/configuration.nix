{ config, lib, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./../../modules/base.nix
    ./../../modules/server.nix
  ];

  networking.hostName = "hermes";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 8123 6052 5010 5000 ];
  };

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
          "https://dns.cloudflare.com/dns-query"
          "https://dns.google/dns-query"
        ];
        bootstrap_dns = [ "1.1.1.1" "8.8.8.8" ];
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
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "24.05";

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
}
