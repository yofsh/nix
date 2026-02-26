{ config, lib, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    zsh
    starship
    atuin
  ];

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    syntaxHighlighting = {
      enable = true;
      patterns = { "rm -rf *" = "fg=black,bg=red"; };
      styles = { "alias" = "fg=green,bold"; };
      highlighters = [ "main" "brackets" "pattern" ];
    };

    autosuggestions.enable = true;
  };

  programs.starship.enable = true;
  programs.starship.settings = {
    add_newline = false;
    format = "$directory$character";
    right_format = "$all";
    character = {
        success_symbol = "[λ](bold green)";
        error_symbol = "[λ](bold red)";
      };
    cmd_duration = {
      min_time = 100;
      show_milliseconds = true;
    };
    directory = { truncation_length = 5; };
    nix_shell = { disabled = false; };
  };
}
