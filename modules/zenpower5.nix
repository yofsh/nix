{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.zenpower5;

  zenpower5 = config.boot.kernelPackages.callPackage ({ lib, stdenv, kernel, fetchFromGitHub }:
    stdenv.mkDerivation {
      pname = "zenpower5";
      version = "unstable-2026-02-28";

      src = fetchFromGitHub {
        owner = "mattkeenan";
        repo = "zenpower5";
        rev = "66871d8e59c3741e00de2eb1f61c3b64263ed10b";
        hash = "sha256-g0zVTDi5owa6XfQN8vlFwGX+gpRIg+5q1F4EuxAk9Sk=";
      };

      hardeningDisable = [ "pic" ];
      nativeBuildInputs = kernel.moduleBuildDependencies;
      makeFlags = [ "KERNEL_BUILD=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build" ];

      installPhase = ''
        install -D zenpower.ko -t "$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/hwmon/zenpower5/"
      '';

      meta = {
        description = "AMD Zen 1-5 CPU monitoring: temperature, voltage, current, and power via SVI2/RAPL";
        homepage = "https://github.com/mattkeenan/zenpower5";
        license = lib.licenses.gpl2Plus;
        platforms = [ "x86_64-linux" ];
      };
    }
  ) {};

in {
  options.hardware.zenpower5 = {
    enable = lib.mkEnableOption "zenpower5 kernel module for AMD Zen 1-5 CPU monitoring";
  };

  config = lib.mkIf cfg.enable {
    boot.extraModulePackages = [ zenpower5 ];
    boot.kernelModules = [ "zenpower" ];
    boot.blacklistedKernelModules = [ "k10temp" ];
  };
}
