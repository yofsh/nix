{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    mangohud
    protonup-qt
    vulkan-hdr-layer-kwin6
  ];

  environment.sessionVariables = {
    DXVK_HDR = "1";
    ENABLE_HDR_WSI = "1";
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
