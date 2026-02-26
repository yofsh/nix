{ config, inputs, lib, pkgs, ... }: {

  imports = [
    ./hardware-configuration.nix
    ./../../modules/base.nix
    ./../../modules/desktop.nix
    ./../../modules/lsp.nix
    ./../../modules/nvidia.nix
  ];
  networking.hostName = "ares";

  environment.systemPackages = [ pkgs.android-tools ];
}
