{ config, inputs, lib, pkgs, ... }:

let
  cfg = config.hardware.mediatek-mt7927;

  repoSrc = inputs.mt7927-dkms;

  # Parse PKGBUILD for firmware and kernel version metadata
  pkgbuild = builtins.readFile "${repoSrc}/PKGBUILD";

  driverFilename =
    let m = builtins.match ".*_driver_filename='([^']+)'.*" pkgbuild;
    in if m != null then builtins.head m
       else "DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip";

  driverSha256Hex =
    let m = builtins.match ".*_driver_sha256='([a-f0-9]+)'.*" pkgbuild;
    in if m != null then builtins.head m
       else "b377fffa28208bb1671a0eb219c84c62fba4cd6f92161b74e4b0909476307cc8";

  mt76KVer =
    let m = builtins.match ".*_mt76_kver='([^']+)'.*" pkgbuild;
    in if m != null then builtins.head m
       else "6.19.10";

  # Kernel source (mt76 + bluetooth drivers)
  # Hash must be updated when mt76KVer changes upstream
  linuxDrivers = pkgs.fetchzip {
    url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/snapshot/linux-${mt76KVer}.tar.gz";
    hash = "sha256-i0u8lQZE+GUtk79CGyjZfdXXzwO7Tv5gGVTPm3nlXM0=";
  };

  # ASUS firmware archive
  asusZip = pkgs.fetchurl {
    url = "https://dlcdnets.asus.com/pub/ASUS/mb/08WIRELESS/${driverFilename}";
    hash = "sha256:${driverSha256Hex}";
    name = "asus-mt7927-driver.zip";
  };

  mkMt7927 = kernel:
    let
      isClang = kernel.stdenv.cc.isClang or false;
      kernelBuild = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
      makeFlags = if isClang then "LLVM=1 CC=clang" else "";
    in
    {
      firmware = kernel.stdenv.mkDerivation {
        pname = "mediatek-mt7927-firmware";
        version = "2.10";
        dontUnpack = true;
        nativeBuildInputs = [ pkgs.libarchive pkgs.python3 ];

        buildPhase = ''
          runHook preBuild
          bsdtar -xf ${asusZip} mtkwlan.dat
          python3 ${repoSrc}/extract_firmware.py mtkwlan.dat firmware/
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm644 firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin \
            "$out/lib/firmware/mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin"
          install -Dm644 firmware/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin \
            "$out/lib/firmware/mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"
          install -Dm644 firmware/WIFI_RAM_CODE_MT6639_2_1.bin \
            "$out/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin"
          runHook postInstall
        '';

        meta.license = lib.licenses.unfreeRedistributableFirmware;
      };

      wifi = kernel.stdenv.mkDerivation {
        pname = "mediatek-mt7927-wifi";
        version = "2.10";
        src = "${linuxDrivers}/drivers/net/wireless/mediatek/mt76";
        nativeBuildInputs = kernel.moduleBuildDependencies ++ [
          pkgs.python3 pkgs.perl pkgs.kmod
        ];

        patches = [
          "${repoSrc}/mt7902-wifi-6.19.patch"
          "${repoSrc}/mt7927-wifi-01-fix-stale-pointer-comparisons-in-changev.patch"
          "${repoSrc}/mt7927-wifi-02-add-320mhz-bandwidth-to-bssrlmtlv.patch"
          "${repoSrc}/mt7927-wifi-03-handle-320mhz-bandwidth-in-rxv-and-txs.patch"
          "${repoSrc}/mt7927-wifi-04-populate-eht-320mhz-mcs-map-in-starec.patch"
          "${repoSrc}/mt7927-wifi-05-advertise-eht-320mhz-capabilities-for-6g.patch"
          "${repoSrc}/mt7927-wifi-06-add-mt7927-chip-id-helpers.patch"
          "${repoSrc}/mt7927-wifi-07-add-mt7927-firmware-paths.patch"
          "${repoSrc}/mt7927-wifi-08-use-irqmap-for-chip-specific-interrupt-h.patch"
          "${repoSrc}/mt7927-wifi-09-add-chip-specific-dma-configuration.patch"
          "${repoSrc}/mt7927-wifi-10-add-mt7927-hardware-initialization.patch"
          "${repoSrc}/mt7927-wifi-11-fix-bandidx-for-stable-5ghz6ghz-operatio.patch"
          "${repoSrc}/mt7927-wifi-12-disable-aspm-and-runtime-pm-for-mt7927.patch"
          "${repoSrc}/mt7927-wifi-13-enable-mt7927-pci-device-ids.patch"
        ];

        postPatch = ''
          cp ${repoSrc}/mt76.Kbuild Kbuild
          cp ${repoSrc}/mt7921.Kbuild mt7921/Kbuild
          cp ${repoSrc}/mt7925.Kbuild mt7925/Kbuild

          mkdir -p compat/include/linux/soc/airoha
          cp ${repoSrc}/compat-airoha-offload.h \
             compat/include/linux/soc/airoha/airoha_offload.h
        '';

        buildPhase = ''
          runHook preBuild
          make -C ${kernelBuild} M=$(pwd) ${makeFlags} modules
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          modDir="$out/lib/modules/${kernel.modDirVersion}/extra/mt76"
          install -dm755 "$modDir/mt7921" "$modDir/mt7925"
          install -m644 mt76.ko mt76-connac-lib.ko mt792x-lib.ko "$modDir/"
          install -m644 mt7921/*.ko "$modDir/mt7921/"
          install -m644 mt7925/*.ko "$modDir/mt7925/"
          runHook postInstall
        '';
      };

      bluetooth = kernel.stdenv.mkDerivation {
        pname = "mediatek-mt7927-bluetooth";
        version = "2.10";
        src = "${linuxDrivers}/drivers/bluetooth";
        nativeBuildInputs = kernel.moduleBuildDependencies ++ [ pkgs.kmod ];

        patches = [
          "${repoSrc}/mt6639-bt-01-add-mt6639-mt7927-bluetooth-support.patch"
          "${repoSrc}/mt6639-bt-02-fix-iso-interface-setup-for-single-alt-s.patch"
          "${repoSrc}/mt6639-bt-03-add-mt7927-id-for-asus-rog-crosshair-x87.patch"
          "${repoSrc}/mt6639-bt-04-add-mt7927-id-for-lenovo-legion-pro-7-16.patch"
          "${repoSrc}/mt6639-bt-05-add-mt7927-id-for-gigabyte-z790-aorus-ma.patch"
          "${repoSrc}/mt6639-bt-06-add-mt7927-id-for-msi-x870e-ace-max.patch"
          "${repoSrc}/mt6639-bt-07-add-mt7927-id-for-tp-link-archer-tbe550e.patch"
          "${repoSrc}/mt6639-bt-08-add-mt7927-id-for-asus-x870e--proart-x87.patch"
        ];

        buildPhase = ''
          runHook preBuild
          cp ${repoSrc}/bluetooth.Makefile Makefile
          make -C ${kernelBuild} M=$(pwd) ${makeFlags} modules
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          modDir="$out/lib/modules/${kernel.modDirVersion}/extra/bluetooth"
          install -dm755 "$modDir"
          install -m644 btusb.ko btmtk.ko "$modDir/"
          runHook postInstall
        '';
      };
    };

in {
  options.hardware.mediatek-mt7927 = {
    enable = lib.mkEnableOption "MediaTek MT7927 / MT6639 WiFi and Bluetooth";
    enableWifi = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    enableBluetooth = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    disableAspm = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkIf cfg.enable (
    let builtModules = mkMt7927 config.boot.kernelPackages.kernel;
    in {
      hardware.firmware = [ builtModules.firmware ];
      boot.extraModulePackages =
        lib.optional cfg.enableWifi builtModules.wifi
        ++ lib.optional cfg.enableBluetooth builtModules.bluetooth;

      boot.kernelModules =
        lib.optionals cfg.enableWifi [ "mt7925e" "mt7921e" ]
        ++ lib.optionals cfg.enableBluetooth [ "btmtk" "btusb" ];

      services.udev.extraRules = lib.mkIf cfg.disableAspm ''
        ACTION=="add", SUBSYSTEM=="pci", \
          ATTR{vendor}=="0x14c3", ATTR{device}=="0x7927", \
          ATTR{link/l1_aspm}="0"
      '';
    }
  );
}
