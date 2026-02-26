{ inputs, config, pkgs, lib, ... }:
let
  link = config.lib.file.mkOutOfStoreSymlink;
  dotfiles = "${config.home.homeDirectory}/nix/dotfiles";
in {

  home.stateVersion = "24.05";

  imports = [ ./xdg.nix ./firefox.nix ./theming.nix ];

  nixpkgs.config.allowUnfree = true;

  home.username = "fobos";
  home.homeDirectory = "/home/fobos";

  # Packages that should be installed to the user profile.
  home.packages = [
    pkgs.libnotify
    pkgs.playerctl
    inputs.claude-code.packages.${pkgs.system}.default
    pkgs.glow

    # Voice transcription
    (pkgs.python312.withPackages (ps: [ ps.faster-whisper ps.evdev ]))

    inputs.hyprland-preview-share-picker.packages.${pkgs.system}.default
  ];

  programs.home-manager.enable = true;
  services.playerctld.enable = true;

  services.vicinae = {
    enable = true;
    package = pkgs.vicinae;
    systemd = {
      enable = true;
      autoStart = true;
      environment = {
        USE_LAYER_SHELL = "1";
      };
    };
  };

  # Prevent vicinae from killing browsers on stop/restart.
  # Apps launched via vicinae end up in its cgroup; without this,
  # systemd SIGKILLs them when the service stops (e.g. compositor crash).
  systemd.user.services.vicinae.Service.KillMode = lib.mkForce "process";

  programs.difftastic.enable = true;
  programs.difftastic.git.enable = true;

  programs.lazygit.enable = true;
  programs.lazygit.settings.gui.border = "hidden";

  programs.git = {
    enable = true;
    settings.user.name = "yofsh";
    settings.user.email = "to@yof.sh";
  };

  xdg.configFile = {
    "xdg-desktop-portal/hyprland-portals.conf".text = ''
      [preferred]
      default=hyprland;gtk
      org.freedesktop.impl.portal.Settings=gtk
    '';

    "foot/foot.ini".source = link "${dotfiles}/foot/foot.ini";
    "dunst/dunstrc".source = link "${dotfiles}/dunst/dunstrc";
    "tridactyl/tridactylrc".source = link "${dotfiles}/firefox/tridactylrc";
    "nvim".source = link "${dotfiles}/nvim";
    "yazi".source = link "${dotfiles}/yazi";
    "hypr".source = link "${dotfiles}/hypr";
    "wiremix".source = link "${dotfiles}/wiremix";
    "mpv/mpv.conf".source = link "${dotfiles}/mpv/mpv.conf";
  };

  home.file = {
    ".zshrc".source = link "${dotfiles}/.zshrc";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
  };

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

  systemd.user.targets.tray = {
    Unit = {
      Description = "Home Manager System Tray";
      Requires = [ "graphical-session-pre.target" ];
    };
  };

}
