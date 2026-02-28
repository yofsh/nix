# Athena-specific: touchpad edge gestures.
{ config, ... }:
let
  dotfiles = "${config.home.homeDirectory}/nix/dotfiles";
in {
  systemd.user.services.edge-sliderd = {
    Unit = {
      Description = "Touchpad edge gesture daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${dotfiles}/bin/edge-sliderd";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  systemd.user.services.edge-slider-actions = {
    Unit = {
      Description = "Edge slider action consumer";
      After = [ "edge-sliderd.service" "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      Requires = [ "edge-sliderd.service" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${dotfiles}/bin/edge-slider-actions";
      LogRateLimitIntervalSec = 0;
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

}
