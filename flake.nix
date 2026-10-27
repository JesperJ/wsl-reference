{
  description = "Shared NixOS-WSL baseline for developer machines";

  # Stable release, not unstable: this is a base many people rebuild from, so a
  # broken unstable bump would break everyone at once. Projects that need newer
  # tools get them from their own devenv.nix, which pins its own nixpkgs.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-wsl, ... }:
    let
      system = "x86_64-linux";
      lib = nixpkgs.lib;
    in
    {
      # The real interface. Everything is an option under `company.*`, so a
      # consumer who needs to deviate imports this into their own nixosSystem
      # and overrides, instead of forking.
      nixosModules = {
        default = self.nixosModules.wsl-dev;
        wsl-dev = {
          imports = [
            nixos-wsl.nixosModules.default
            home-manager.nixosModules.home-manager
            ./modules/nixos
          ];
        };
      };

      # The 15-line path: a machine is a name, a user and a few facts.
      lib.mkWsl = import ./lib/mkWsl.nix { inherit nixpkgs self; };

      templates.default = {
        path = ./templates/default;
        description = "A personal WSL machine built on the shared baseline";
      };

      # Built in CI so a change to the baseline is proven to evaluate and build
      # before anyone rebuilds from it.
      nixosConfigurations.example = self.lib.mkWsl {
        hostName = "wsl-example";
        user = {
          name = "dev";
          fullName = "Example Developer";
          email = "dev@example.com";
        };
      };

      checks.${system}.example =
        self.nixosConfigurations.example.config.system.build.toplevel;

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
