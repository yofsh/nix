{ ... }:
{
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true; # Wayland (Hyprland) DRM/KMS capture
    openFirewall = true;
  };

  hardware.uinput.enable = true;
  users.users.fobos.extraGroups = [ "uinput" ];
}
