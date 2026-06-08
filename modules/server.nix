{ lib, ... }: {

  zramSwap.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.containers.enable = true;

  # Both servers boot via UEFI/systemd-boot.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Firewall on; each host opens its own service ports via allowedTCPPorts.
  networking.firewall.enable = true;

  # Servers use full starship prompt (no right-align split)
  programs.starship.settings.add_newline = lib.mkForce true;
  programs.starship.settings.format = lib.mkForce "$all$directory$character";
  programs.starship.settings.right_format = lib.mkForce "";
}
