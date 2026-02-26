let
  common = import ./common.nix;
in
{
  disko.devices = {
    disk = {
      vdb = {
        type = "disk";
        device = "REPLACE_ME";
        content = {
          type = "gpt";
          partitions = {
            ESP = common.espPartition;
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                settings.allowDiscards = true;
                passwordFile = "/tmp/secret.key";
                content = common.btrfsSubvolumes;
              };
            };
          };
        };
      };
    };
  };
}
