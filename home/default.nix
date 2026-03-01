{ inputs, config, pkgs, lib, ... }:
let
  link = config.lib.file.mkOutOfStoreSymlink;
  dotfiles = "${config.home.homeDirectory}/nix/dotfiles";
  hostname = lib.strings.trim (builtins.readFile "/etc/hostname");
in {

  home.stateVersion = "24.05";

  imports = [ ./xdg.nix ./firefox.nix ./theming.nix ]
    ++ lib.optionals (hostname == "athena") [ ./touchpad.nix ./laptop.nix ];

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
    "tridactyl/tridactylrc".source = link "${dotfiles}/firefox/tridactylrc";
    "nvim".source = link "${dotfiles}/nvim";
    "yazi".source = link "${dotfiles}/yazi";
    "hypr".source = link "${dotfiles}/hypr";
    "wiremix".source = link "${dotfiles}/wiremix";
    "mpv/mpv.conf".source = link "${dotfiles}/mpv/mpv.conf";

    # Source home-manager session vars into uwsm so sessionPath/sessionVariables
    # are available to Hyprland and all graphical apps launched by it.
    "uwsm/env".text = ''
      source "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    '';
  };

  home.file = {
    ".zshrc".source = link "${dotfiles}/.zshrc";
  };

  home.sessionPath = [
    "${dotfiles}/bin"
    "${dotfiles}/bin/utils"
  ];

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "firefox";
  };

  systemd.user.targets.tray = {
    Unit = {
      Description = "Home Manager System Tray";
      Requires = [ "graphical-session-pre.target" ];
    };
  };

}
