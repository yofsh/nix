{ config, pkgs, ... }: {

  environment.systemPackages = [ pkgs.nvtopPackages.nvidia ];

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics.extraPackages = [ pkgs.nvidia-vaapi-driver ];

  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = false;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Docker with NVIDIA Container Toolkit (CDI)
  virtualisation.docker.enable = true;
  virtualisation.docker.enableNvidia = true;
  hardware.nvidia-container-toolkit.enable = true;
  virtualisation.docker.daemon.settings = {
    features = {
      cdi = true;
    };
  };
}
