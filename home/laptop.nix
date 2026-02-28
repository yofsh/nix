# Athena-specific: IIO sensor auto-rotation for convertible/tablet use.
{ pkgs, ... }:
{
  home.packages = [ pkgs.iio-hyprland ];

  systemd.user.services.iio-hyprland = {
    Unit = {
      Description = "IIO sensor auto-rotation for Hyprland";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.iio-hyprland}/bin/iio-hyprland";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
