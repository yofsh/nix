{
  description = "System config";

  nixConfig = {
    extra-substituters = [ "https://vicinae.cachix.org" ];
    extra-trusted-public-keys = [ "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc=" ];
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
    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
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
          ./hosts/ares/configuration.nix
          { nixpkgs.overlays = [ inputs.quickshell.overlays.default ]; }
        ];
      };

      nixosConfigurations.athena = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/athena/configuration.nix
          sops-nix.nixosModules.sops
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
