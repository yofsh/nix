let
  common = import ./common.nix;
in
{
  disko.devices = {
    disk = {
      main = {
        device = "REPLACE_ME_1";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = common.espPartition;
            swap = common.swapPartition "32G";
            root = {
              size = "100%";
              # Data striped (raid0), metadata mirrored (raid1) across both disks.
              # The second disk is passed as a raw device — no partition table needed.
              content = common.btrfsSubvolumes // {
                extraArgs = [
                  "-f"
                  "-d"
                  "raid0"
                  "-m"
                  "raid1"
                  "REPLACE_ME_2"
                ];
              };
            };
          };
        };
      };
    };
  };
}
