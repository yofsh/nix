{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    tree-sitter # nvim-treesitter (main branch) compiles parsers via `tree-sitter build`
    stylua
    nixfmt
    shfmt
    yq
    lua-language-server
    yaml-language-server
    bash-language-server
    typescript-language-server
    typescript
    nixd
    vscode-langservers-extracted
    shellcheck
  ];
}

