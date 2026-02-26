let
  common = import ./common.nix;
in
{
  disko.devices = {
    disk = {
      my-disk = {
        device = "REPLACE_ME";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = common.espPartition;
            swap = common.swapPartition "32G";
            root = {
              size = "100%";
              content = common.btrfsSubvolumes;
            };
          };
        };
      };
    };
  };
}
