{ config, lib, pkgs, ... }:
{
  programs.ssh.startAgent = false;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];
}
