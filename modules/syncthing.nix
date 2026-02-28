{ config, lib, pkgs, ... }: {

  services.syncthing = {
    enable = true;
    user = "fobos";
    dataDir = "/home/fobos";
    configDir = "/home/fobos/.config/syncthing";
    openDefaultPorts = true;
    overrideDevices = false;
    overrideFolders = false;

    settings = {
      options.urAccepted = -1;

      folders."claude-config" = {
        path = "/home/fobos/.claude";
        ignorePatterns = [
          "cache"
          "backups"
          "debug"
          "file-history"
          "session-env"
          "shell-snapshots"
          "paste-cache"
          "plans"
          "todos"
          "history.jsonl"
          "credentials.json"
          "mcp-needs-auth-cache.json"
          "statsig"
          ".dat*"
        ];
      };
    };
  };
}
