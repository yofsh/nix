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
    ./../../modules/transmission.nix
    ./../../modules/mt7927.nix
  ];
  networking.hostName = "ares";
  networking.interfaces.enp113s0.wakeOnLan.enable = true;

  hardware.mediatek-mt7927 = {
    enable = true;
    enableWifi = true;
    enableBluetooth = true;
    disableAspm = true;
  };

  hardware.zenpower5.enable = true;

  # MT7925/MT7927 WiFi tuning — disable CLC region-based Tx power caps
  boot.extraModprobeConfig = ''
    options mt7925-common disable_clc=1
  '';

  # NCT6799D Super I/O chip - fan speed monitoring
  boot.kernelModules = [ "nct6775" ];
  boot.kernelParams = [
    "acpi_enforce_resources=lax"
    "pcie_aspm=off"
    "cfg80211.ieee80211_regdom=DE" # 6GHz needs persistent regdom, not beacon hints
  ];

  environment.systemPackages = [ pkgs.android-tools pkgs.hyperhdr pkgs.monique pkgs.dokit ];
}
