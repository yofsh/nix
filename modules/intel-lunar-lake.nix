{ config, lib, pkgs, ... }:
{
  # Intel GPU (iHD VA-API + Quick Sync)
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vpl-gpu-rt
  ];
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # GPU load monitoring (intel_gpu_top, used by the quickshell `gpu` widget).
  environment.systemPackages = [ pkgs.intel-gpu-tools ];

  # intel_gpu_top reads the i915/Xe PMU, which needs CAP_PERFMON. Wrap just that
  # binary with the capability so it runs as the user without lowering the global
  # perf_event_paranoid policy. /run/wrappers/bin precedes the plain package on PATH.
  security.wrappers.intel_gpu_top = {
    owner = "root";
    group = "root";
    capabilities = "cap_perfmon+ep";
    source = "${pkgs.intel-gpu-tools}/bin/intel_gpu_top";
  };
}
