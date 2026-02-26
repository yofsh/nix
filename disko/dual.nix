let
  common = import ./common.nix;
in
{
  disko.devices = {
    disk = {
      disk1 = {
        device = "REPLACE_ME_1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = common.espPartition;
            swap = common.swapPartition "32G";
            root = {
              size = "100%";
              # Data striped (raid0), metadata mirrored (raid1) across both disks
              content = common.btrfsSubvolumes // {
                extraArgs = [
                  "-f"
                  "-d"
                  "raid0"
                  "-m"
                  "raid1"
                  "REPLACE_ME_2_PART"
                ];
              };
            };
          };
        };
      };
      disk2 = {
        device = "REPLACE_ME_2";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            # No content — included in disk1's mkfs.btrfs
            data = {
              size = "100%";
            };
          };
        };
      };
    };
  };
}
