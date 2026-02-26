{ config, lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./../../modules/base.nix
    ./../../modules/desktop.nix
    ./../../modules/lsp.nix
    ./../../modules/sops.nix
    ./../../modules/fingerprint.nix
    ./../../modules/security-keys.nix
    ./../../modules/intel-lunar-lake.nix
  ];
  networking.hostName = "athena";

  services.usbmuxd.enable = true;
  services.udev.extraRules = ''
    # InfiRay P2 Pro thermal camera - allow non-root USB access
    SUBSYSTEM=="usb", ATTR{idVendor}=="0bda", ATTR{idProduct}=="5830", MODE="0660", GROUP="video"
  '';

  programs.light.enable = true;

  # IIO sensors (accelerometer, gyro, etc.) — needed for auto-rotation
  hardware.sensor.iio.enable = true;
  systemd.services.iio-sensor-proxy = {
    wantedBy = [ "multi-user.target" ];
    # IIO devices may appear before udev rules populate IIO_SENSOR_PROXY_TYPE,
    # causing the proxy to see no sensors and exit. Retrigger udev first.
    serviceConfig.ExecStartPre = "${pkgs.systemd}/bin/udevadm trigger --subsystem-match=iio";
  };
  environment.systemPackages = [ pkgs.iio-hyprland ];

  sops.secrets."testkey" = {
    owner = config.users.users.fobos.name;
  };
}
