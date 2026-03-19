{ config, lib, pkgs, ... }: {
  services.transmission = {
    enable = true;
    user = "fobos";
    group = "users";
    package = pkgs.transmission_4;
    settings = {
      # Watch ~/dl for .torrent files, auto-add them
      watch-dir-enabled = true;
      watch-dir = "/home/fobos/dl";

      # Save completed downloads to ~/dl/torrents
      download-dir = "/home/fobos/dl/torrents";

      # Stop seeding immediately after download completes (ratio 0)
      ratio-limit-enabled = true;
      ratio-limit = 0;

      # Disable idle seeding limit as well
      idle-seeding-limit-enabled = true;
      idle-seeding-limit = 0;

      # RPC for CLI control (transmission-remote)
      rpc-bind-address = "127.0.0.1";
      rpc-whitelist-enabled = true;
      rpc-whitelist = "127.0.0.1";
    };
  };
}
