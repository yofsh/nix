{ config, ... }:
{
  sops.defaultSopsFile = ./../secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.age.keyFile = "";
  sops.age.generateKey = false;

  sops.secrets."deepl-key" = {
    owner = config.users.users.fobos.name;
  };
  sops.secrets."ha-token" = {
    owner = config.users.users.fobos.name;
  };
  sops.secrets."paperless-token" = {
    owner = config.users.users.fobos.name;
  };
  sops.secrets."unsplash-key" = {
    owner = config.users.users.fobos.name;
  };
}
