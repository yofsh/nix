{ config, lib, pkgs, inputs, ... }:
let
  netwatch = pkgs.rustPlatform.buildRustPackage rec {
    pname = "netwatch-tui";
    version = "0.23.0";
    src = pkgs.fetchCrate {
      inherit pname version;
      hash = "sha256-qk7ydVqcUU/OEfUG/xaF/NDmG/vq0GTvmfOmlV8645Y=";
    };
    cargoHash = "sha256-2+Hy5wYiij26NBjbahZfu0gqXwL7qifBY8jCo3O5sYg=";
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.libpcap ];
  };

  netscan = pkgs.rustPlatform.buildRustPackage rec {
    pname = "netscan-tui";
    version = "0.8.1";
    src = pkgs.fetchCrate {
      inherit pname version;
      hash = "sha256-b+nrTCr5aaUON0QLV7S8qJbBCoO7m91nbOikBoaaK1k=";
    };
    cargoHash = "sha256-4mhVNr62NrCPR5W7Qkfg2LAPInOltyfG/nyITROEKJY=";
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    # netscan shells out to nmap at runtime
    postInstall = ''
      wrapProgram $out/bin/netscan \
        --prefix PATH : ${lib.makeBinPath [ pkgs.nmap ]}
    '';
  };
in
{

  imports = [ ./audio.nix ./printing.nix ./boot-desktop.nix ./gaming.nix ];

  environment.systemPackages = with pkgs; [
    (google-chrome.override {
      commandLineArgs =
        [ "--enable-features=UseOzonePlatform" "--ozone-platform=wayland" ];
    })

    #GUI tools
    telegram-desktop
    obsidian
    foot
    mpv
    imv
    # krita
    orca-slicer
    yubikey-personalization
    godot_4

    #TUI utils
    yazi
    p7zip # for yazi archive extraction
    inputs.net-tui.packages.${pkgs.system}.wifi-tui
    inputs.net-tui.packages.${pkgs.system}.bt-tui
    netwatch
    netscan
    powertop
    config.boot.kernelPackages.cpupower

    # CLI utils
    gnupg
    proxmark3
    rbw
    bluez
    bluez-tools
    udiskie
    socat
    libqalculate
    tesseract
    bat
    wirelesstools
    iw

    # Shell frameworks
    quickshell

    # WMs and stuff
    pyprland
    hyprpicker
    hyprcursor
    hyprlock
    hypridle
    # hyprpaper
    awww
    brightnessctl
    ddcutil
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    gsettings-desktop-schemas
    xdg-user-dirs
    xdg-utils
    wdisplays
    hyprsunset

    wl-clipboard
    wtype
    wev

    # Screen capture
    grim
    slurp
    satty
    wf-recorder
    aichat

    # Other
    home-manager
    materia-theme
    papirus-icon-theme
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
    twemoji-color-font
    font-awesome
    powerline-fonts
    powerline-symbols
    nerd-fonts.symbols-only
    nerd-fonts.dejavu-sans-mono
  ];

  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "en_US.UTF-8";

  system.stateVersion = "26.05";

  # DDC/CI for external monitor brightness control via I2C
  boot.kernelModules = [ "i2c-dev" ];
  hardware.i2c.enable = true;

  security.pam.services.hyprlock = {};
  security.polkit.enable = true;
  services.fstrim.enable = true;
  security.rtkit.enable = true;

  security.wrappers.cpupower = {
    source = "${config.boot.kernelPackages.cpupower}/bin/cpupower";
    owner = "root";
    group = "wheel";
    setuid = true;
  };

  # Flatpak
  services.flatpak.enable = true;

  services.fwupd.enable = true;
  services.tuned.enable = true;
  services.tuned.ppdSupport = true;
  services.gvfs.enable = true;
  services.udisks2.enable = true;
  services.locate.enable = true;

  # Software
  programs.noisetorch.enable = true;
  services.upower.enable = true;

  programs.firefox.enable = true;
  programs.firefox.policies = {
    NewTabPage = false;
    CaptivePortal = true;
    DisableFirefoxStudies = true;
    DisablePocket = true;
    DisableTelemetry = true;
    NoDefaultBookmarks = true;
    OfferToSaveLogins = false;
    OfferToSaveLoginsDefault = false;
    PasswordManagerEnabled = false;
    FirefoxHome = {
      Search = true;
      Pocket = false;
      Snippets = false;
      TopSites = false;
      Highlights = false;
    };
    UserMessaging = {
      ExtensionRecommendations = false;
      SkipOnboarding = true;
    };
    Preferences = {
      "ui.key.menuAccessKeyFocuses" = {
        Status = "locked";
        Value = false;
      };
    };
  };

  programs.dconf.enable = true;
  programs.kdeconnect.enable = true;
  programs.hyprland.enable = true;
  programs.hyprland.withUWSM = true;
  programs.hyprland.xwayland.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  environment.sessionVariables.BROWSER = "firefox";
  environment.sessionVariables.EDITOR = "nvim";

  services.greetd = {
    enable = true;
    restart = false;
    settings = {
      default_session = {
        command = "uwsm start hyprland-uwsm.desktop";
        user = "fobos";
      };
      initial_session = {
        command = "uwsm start hyprland-uwsm.desktop";
        user = "fobos";
      };
    };
  };

  networking.wireless.iwd.enable = false;
  networking.networkmanager.wifi.backend = "wpa_supplicant";
}
