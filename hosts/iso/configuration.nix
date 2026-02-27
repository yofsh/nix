{ pkgs, modulesPath, lib, ... }:
let
  nix-src = pkgs.fetchFromGitHub {
    owner = "yofsh";
    repo = "nix";
    rev = "2ca66267a4c56b176421ec3a1728834710720f16";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
{

  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
    ./../../modules/base.nix
    ./../../modules/desktop.nix
  ];

  # iso uses grub by default
  boot.loader.systemd-boot.enable = lib.mkForce false;

  nixpkgs.hostPlatform = "x86_64-linux";

  # Trust flake-configured substituters (cachix, CUDA cache) during nixos-install
  nix.settings = {
    trusted-substituters = [
      "https://vicinae.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-public-keys = [
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
    accept-flake-config = true;
  };

  # Bake repo snapshot into the ISO for offline use
  system.activationScripts.seedRepos = ''
    if [[ ! -d /home/fobos/nix ]]; then
      cp -r ${nix-src} /home/fobos/nix
      chmod -R u+w /home/fobos/nix
      chown -R fobos:users /home/fobos/nix
    fi
  '';

  # Replace snapshot with proper git clone once network is available
  systemd.services.clone-repos = {
    description = "Clone repos into home directory";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "fobos";
      ExecStart = pkgs.writeShellScript "clone-repos" ''
        if [[ ! -d /home/fobos/nix/.git ]]; then
          rm -rf /home/fobos/nix
          ${pkgs.git}/bin/git clone https://github.com/yofsh/nix.git /home/fobos/nix
        fi
      '';
    };
  };
}
