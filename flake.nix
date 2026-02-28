{
  description = "System config";

  nixConfig = {
    extra-substituters = [
      "https://vicinae.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    extra-trusted-public-keys = [
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix.url = "github:Mic92/sops-nix";
    claude-code.url = "github:sadjow/claude-code-nix";
    vicinae.url = "github:vicinaehq/vicinae";
    hyprland-preview-share-picker.url = "git+https://github.com/WhySoBad/hyprland-preview-share-picker?submodules=1";
    mt7927.url = "github:cmspam/mt7927-nixos";
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    silent-sddm = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, ... }@inputs:

    let
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};

    in {

      nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/iso/configuration.nix
          inputs.silent-sddm.nixosModules.default

          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs; };
            home-manager.sharedModules = [
              inputs.vicinae.homeManagerModules.default
            ];
            home-manager.users.fobos = import ./home/default.nix;
            nixpkgs.overlays = [ inputs.quickshell.overlays.default ];
          }
        ];
      };

      nixosConfigurations.ares = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          inputs.mt7927.nixosModules.default
          sops-nix.nixosModules.sops
          ./hosts/ares/configuration.nix
          inputs.silent-sddm.nixosModules.default
          { nixpkgs.overlays = [ inputs.quickshell.overlays.default ]; }
        ];
      };

      nixosConfigurations.athena = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/athena/configuration.nix
          sops-nix.nixosModules.sops
          inputs.silent-sddm.nixosModules.default
          { nixpkgs.overlays = [ inputs.quickshell.overlays.default ]; }
        ];
      };

      nixosConfigurations.hermes = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/hermes/configuration.nix ];
      };

      nixosConfigurations.demeter = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./hosts/demeter/configuration.nix ];
      };

      homeConfigurations.fobos = home-manager.lib.homeManagerConfiguration {
        extraSpecialArgs = { inherit inputs; };
        inherit pkgs;
        modules = [
          ./home/default.nix
          inputs.vicinae.homeManagerModules.default
        ];
      };
    };
}
