{ pkgs, ... }:
{
  # Persistent BLE daemon for the Pokit multimeter widget. Keeps one
  # GATT connection alive so the widget avoids paying the 15-20s
  # scan+connect+discovery cost on every op.
  #
  # Ops:
  #   systemctl --user status pokitd
  #   journalctl --user -u pokitd -f
  #   printf '{"type":"ping"}\n' | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/pokitd/sock
  systemd.user.services.pokitd = {
    Unit = {
      Description = "Pokit multimeter BLE daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.pokitd}/bin/pokitd";
      Restart = "on-failure";
      RestartSec = 3;
      RuntimeDirectory = "pokitd";
      StandardOutput = "journal";
      StandardError = "journal";
      NoNewPrivileges = true;
      RestrictAddressFamilies = "AF_UNIX AF_BLUETOOTH AF_NETLINK";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
