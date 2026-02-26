let
  common = import ./common.nix;
in
{
  disko.devices = {
    disk = {
      backupstorage = {
        type = "disk";
        device = "REPLACE_ME";
        content = {
          type = "gpt";
          partitions = {
            secrets = common.mkLuksPartition {
              name = "secrets";
              size = "32M";
              priority = 1;
              passwordFile = "/home/fobos/nix/1.key";
              label = "secrets";
            };
            private = common.mkLuksPartition {
              name = "private";
              size = "4G";
              priority = 3;
              passwordFile = "/home/fobos/nix/2.key";
              label = "private";
            };
            storage = common.mkLuksPartition {
              name = "storage";
              size = "100G";
              priority = 4;
              passwordFile = "/home/fobos/nix/3.key";
              label = "storage";
            };
          };
        };
      };
    };
  };
}
