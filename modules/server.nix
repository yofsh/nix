{ lib, ... }: {

  zramSwap.enable = true;

  virtualisation.docker.enable = true;
  virtualisation.containers.enable = true;

  # Servers use full starship prompt (no right-align split)
  programs.starship.settings.add_newline = lib.mkForce true;
  programs.starship.settings.format = lib.mkForce "$all$directory$character";
  programs.starship.settings.right_format = lib.mkForce "";
}
