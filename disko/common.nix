{
  btrfsOpts = [ "compress=zstd" "noatime" ];

  espPartition = {
    type = "EF00";
    size = "2G";
    content = {
      type = "filesystem";
      format = "vfat";
      mountpoint = "/boot";
    };
  };

  swapPartition = size: {
    inherit size;
    content = {
      type = "swap";
      resumeDevice = true;
    };
  };

  btrfsSubvolumes = {
    type = "btrfs";
    extraArgs = [ "-f" ];
    subvolumes = {
      "@" = {
        mountpoint = "/";
        mountOptions = [ "compress=zstd" "noatime" ];
      };
      "@home" = {
        mountpoint = "/home";
        mountOptions = [ "compress=zstd" "noatime" ];
      };
      "@nix" = {
        mountpoint = "/nix";
        mountOptions = [ "compress=zstd" "noatime" ];
      };
      "@log" = {
        mountpoint = "/var/log";
        mountOptions = [ "compress=zstd" "noatime" ];
      };
      "@docker" = {
        mountpoint = "/var/lib/docker";
        mountOptions = [ "noatime" "nodatacow" ];
      };
      "@snapshots" = {
        mountpoint = "/.snapshots";
        mountOptions = [ "compress=zstd" "noatime" ];
      };
    };
  };

  mkLuksPartition =
    {
      name,
      passwordFile,
      label,
      size,
      priority ? null,
    }:
    {
      inherit size;
      content = {
        type = "luks";
        inherit name;
        settings.allowDiscards = true;
        inherit passwordFile;
        content = {
          type = "btrfs";
          extraArgs = [ "-f" "-L" label ];
          mountpoint = "/";
          mountOptions = [ "compress=zstd" "noatime" ];
        };
      };
    }
    // (if priority != null then { inherit priority; } else { });
}
