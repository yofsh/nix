{ config, lib, pkgs, ... }:
{
  powerManagement.cpuFreqGovernor = "performance";

  # Intel GPU (iHD VA-API + Quick Sync)
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Fix CPU frequency capping on Lunar Lake (power-profiles-daemon bug)
  systemd.services.uncap-cpu-freq = {
    description = "Uncap CPU frequency limits for Lunar Lake";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
        max=$(dirname $cpu)/cpuinfo_max_freq
        cat $max > $cpu
      done
    '';
  };
}
