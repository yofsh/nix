{ config, lib, pkgs, ... }:
{
  # Intel GPU (iHD VA-API + Quick Sync)
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

}
