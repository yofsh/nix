let
  common = import ./common.nix;
in
{
  disko.devices = {
    disk = {
      main = {
        device = "REPLACE_ME";
        type = "disk";
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
                # Data striped (raid0), metadata mirrored (raid1) across both disks.
                # The second disk must have LUKS opened as /dev/mapper/crypted2
                # before disko runs (handled by the installer).
                content = common.btrfsSubvolumes // {
                  extraArgs = [
                    "-f"
                    "-d"
                    "raid0"
                    "-m"
                    "raid1"
                    "/dev/mapper/crypted2"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
