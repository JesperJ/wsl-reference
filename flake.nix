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
    # The devenv project templates that `devenvify` copies, as a plain SOURCE
    # rather than a flake. `flake = false` on purpose: that repository has a
    # flake.nix, but consuming it would bring its own nixpkgs and build the
    # tool against that. As a source it is just a store path, and dev.nix
    # callPackages the package.nix at its root against OUR pkgs -- so the
    # machine stays on one nixpkgs.
    #
    # Bumping after a template changes: `nix flake update devenv-templates`,
    # then rebuild. No tag to edit: the payload is a shell script and template
    # files, nothing a machine boots.
    devenv-templates = {
      url = "github:JesperJ/devenv-templates";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, home-manager, nixos-wsl, devenv-templates, ... }:
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

          # The templates source, handed to the modules as an argument so
          # ./modules/nixos stays a plain module tree with no flake in scope.
          # It travels with nixosModules.default, so a consumer who imports the
          # module into their own nixosSystem gets it without wiring anything.
          _module.args.devenvTemplates = devenv-templates;
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
