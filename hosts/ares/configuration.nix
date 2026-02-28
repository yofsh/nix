{ config, inputs, lib, pkgs, ... }: {

  imports = [
    ./hardware-configuration.nix
    ./../../modules/base.nix
    ./../../modules/desktop.nix
    ./../../modules/lsp.nix
    ./../../modules/nvidia.nix
    ./../../modules/sops.nix
    ./../../modules/fingerprint.nix
    ./../../modules/zenpower5.nix
    ./../../modules/syncthing.nix
  ];
  networking.hostName = "ares";

  hardware.mediatek-mt7927 = {
    enable = true;
    enableWifi = true;
    enableBluetooth = true;
    disableAspm = true;
  };

  hardware.zenpower5.enable = true;

  # NCT6799D Super I/O chip - fan speed monitoring
  boot.kernelModules = [ "nct6775" ];
  boot.kernelParams = [ "acpi_enforce_resources=lax" "pcie_aspm=off" ];

  environment.systemPackages = [ pkgs.android-tools ];
}
