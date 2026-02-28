{ config, lib, pkgs, ... }: {

  imports = [ ./networking.nix ./shell.nix ];

  nixpkgs.config = { allowUnfree = true; };
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.tmp.useTmpfs = true;

  environment.systemPackages = with pkgs; [
    gnumake
    gcc
    nodejs
    deno
    pnpm
    (python3.withPackages (ps: [ ps.evdev ]))
    yarn

    htop
    glances
    kmon
    sysz
    systemctl-tui
    lazygit
    lazydocker
    docker-compose
    ncdu
    mtr
    psmisc
    lsof

    zellij
    s-tui
    stress
    lnav
    gping
    atac

    fastfetch
    file
    tree
    wget
    git
    grc
    nix-index
    nix-inspect
    nh
    trash-cli
    imagemagick
    lm_sensors

    hyperfine
    ripgrep
    eza
    fd
    bc
    jq
    qrencode
    zoxide
    fzf
    exiftool
    lshw
    pngquant
    smartmontools
    zbar
    gh

    ffmpeg
    ntfs3g
    yt-dlp

    restic
  ];

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
  };

   services.openssh.enable = true;
   # services.tailscale.enable = true;
   services.sysstat.enable = true;
  users = {
    defaultUserShell = pkgs.zsh;


    users.fobos = {
      useDefaultShell = true;
      isNormalUser = true;
      createHome = true;
      description = "fobos";
      extraGroups = [
        "networkmanager"
        "wheel"
        "input"
        "libvirtd"
        "docker"
        "video"
        "nginx"
        "lpadmin"
        "i2c"
      ];
      packages = with pkgs; [ ];
      openssh.authorizedKeys.keys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC1ZWtcOzD0v67ORNy6YxBQxwHtPu8q0IWNzhpvcMGXsxUD5veeRZtuQLSXXf3+0EA+r+iC0K+1gEXAhjjyyKKUVhjzgtSPd+eI85d+BRY/X+8y9EjxAx5I0BFpxI0uSvukhrqLnbzs0/EMjr2yxMPRf66KJ6gpevzW7q9AvAJsxCEOTI8Xv/6WJh+jnqU+BrB86qczcPWbUYuZCEEoQ9HTpPrIWeC0KSgSn94nAQYV3UZjbJSkELyIc2dDDxb9pP+60kr2/J6c4NeSRPWTPjAGdOFjcdqH7oRTLOLMQyk+JimPw8zkp7BDL2TCDpvcTj2RCF4zQ9QeVdyXFwbipKspiCCBl1mXM+mePNtak4jGgc7V9WQjKFz+7CTRoTEteAyIkM/FElxtlKUkxA55UQGh3SA4wxqF0ZbYVKtHgjMNO9uTPsbZy1c0Ixfq9eKIcoKQxNBRx0pavGmKrh9BAMoHPXOqztOrkAJ6ClQzr5eA7a1N23EayFJo/hHvz4ncYrcm+glW11wlTfNbvdHCDsfNcpczK9C+NDPOAI8BER4Q0NOZQ/7HtVnXu2MfXkzeoBX20Xpv8+Br3HJ/T1qQlSn2lkRy+gMFTVZaC/CkrWVpR/xTMU0Ac3T8kIAk34cpLZlH5DqX0Phzqxn+s7c4e/IpQt5RgLbBmwQ3dsp2BnFLlw== user@host"
      ];
    };

  };

  security.sudo = {
    enable = true;
    extraRules = [{
      commands = [
        {
          command = "${pkgs.systemd}/bin/reboot";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.systemd}/bin/poweroff";
          options = [ "NOPASSWD" ];
        }
      ];
      groups = [ "wheel" ];
    }];
  };
}
