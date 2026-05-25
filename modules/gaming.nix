{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    bottles
    mangohud
    protonup-qt
    vesktop
    vulkan-hdr-layer-kwin6
  ];

  environment.sessionVariables = {
    STEAM_ENABLE_PIPEWIRE = "1";
  };

  programs.steam.enable = true;
  programs.steam.gamescopeSession.enable = true;
  programs.steam.remotePlay.openFirewall = true;
  programs.steam.localNetworkGameTransfers.openFirewall = true;
  programs.steam.extraCompatPackages = with pkgs; [ proton-ge-bin ];

  programs.gamemode.enable = true;
  programs.gamescope.enable = true;
  programs.gamescope.capSysNice = false;
}
