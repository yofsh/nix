{pkgs, ...}: let
  browser = ["firefox.desktop"];

  associations = {
    "text/html" = browser;
    "x-scheme-handler/http" = browser;
    "x-scheme-handler/https" = browser;
    "x-scheme-handler/ftp" = browser;
    "x-scheme-handler/about" = browser;
    "x-scheme-handler/unknown" = browser;
    "application/x-extension-htm" = browser;
    "application/x-extension-html" = browser;
    "application/x-extension-shtml" = browser;
    "application/xhtml+xml" = browser;
    "application/x-extension-xhtml" = browser;
    "application/x-extension-xht" = browser;

    "audio/*" = ["mpv.desktop"];
    "video/*" = ["mpv.desktop"];
    "image/*" = ["imv.desktop"];
    "application/json" = browser;
    "application/pdf" = browser;
    "x-scheme-handler/tg" = ["telegramdesktop.desktop"];
  };
in {
  xdg = {
    userDirs = {
      enable = true;
      createDirectories = true;
      documents = "$HOME/docs";
      download = "$HOME/dl";
      videos = "$HOME/vids";
      music = "$HOME/music";
      pictures = "$HOME/pics";
      desktop = "$HOME/desktop";
      publicShare = "$HOME/share";
      templates = "$HOME/docs/templates";
    };
    mimeApps.enable = true;
    mimeApps.associations.added = associations;
    mimeApps.defaultApplications = associations;
  };
}

