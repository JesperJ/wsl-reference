{
  description = "Shared NixOS-WSL baseline for developer machines";

  # Stable release, not unstable: this is a base many people rebuild from, so a
  # broken unstable bump would break everyone at once. Projects that need newer
  # tools get them from their own devenv.nix, which pins its own nixpkgs.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for nixosModules.home-manager, which is opt-in. Kept as an input
    # anyway so opting in costs one line in extraModules instead of a
    # home-manager input of your own plus
    # `inputs.home-manager.inputs.nixpkgs.follows = "wsl-base/nixpkgs"` to keep
    # the two nixpkgs from diverging.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Only used by ./default.nix, the non-flake entry point, which reads this
    # lock to find the revision. Declared as an input rather than pinned by
    # hand so `nix flake update` keeps it current like everything else.
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
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
    # The devenv CLI, pinned to a release of its own so it can run ahead of
    # the stable nixpkgs without moving the rest of the machine. It has to
    # keep up: every project's devenv.yaml pulls current devenv modules, and a
    # CLI older than those spills errors into each shell it loads.
    #
    # Deliberately no `inputs.nixpkgs.follows`: that would change the build,
    # so every machine would compile devenv from source. Left alone, the
    # binary comes prebuilt from devenv.cachix.org, which ./modules/*/nix.nix
    # already trust. Bump by editing the tag, then `nix flake update devenv`.
    devenv.url = "github:cachix/devenv/v2.4.0";
  };

  outputs = { self, nixpkgs, home-manager, nixos-wsl, devenv-templates, devenv, ... }:
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
            ./modules/nixos
          ];

          # The templates source, handed to the modules as an argument so
          # ./modules/nixos stays a plain module tree with no flake in scope.
          # It travels with nixosModules.default, so a consumer who imports the
          # module into their own nixosSystem gets it without wiring anything.
          _module.args.devenvTemplates = devenv-templates;
          _module.args.devenvPackage = devenv.packages.${system}.devenv;
        };

        # Opt-in: declarative dotfiles for someone who wants them. Added to
        # extraModules, never imported by the baseline -- see
        # modules/home-manager.nix for why a shared base leaves $HOME alone.
        home-manager = {
          imports = [
            home-manager.nixosModules.home-manager
            ./modules/home-manager.nix
          ];
        };
      };


      # For a WSL distro that is NOT NixOS -- Ubuntu or Debian with Nix on top.
      # The same company.* options, implemented with only what a user can own;
      # see modules/home/standalone.nix and the README for the handful of
      # things that stay root's job.
      homeModules = {
        default = self.homeModules.wsl-dev;
        wsl-dev = {
          imports = [ ./modules/home/standalone.nix ];

          # Same argument, same reason as nixosModules.wsl-dev: the module tree
          # stays plain, with no flake in scope.
          _module.args.devenvTemplates = devenv-templates;
          _module.args.devenvPackage = devenv.packages.${system}.devenv;
        };
      };

      # The 15-line path: a machine is a name, a user and a few facts.
      lib = {
        mkWsl = import ./lib/mkWsl.nix { inherit nixpkgs self; };
        mkWslHome = import ./lib/mkWslHome.nix { inherit nixpkgs home-manager self; };
      };

      templates = {
        default = {
          path = ./templates/default;
          description = "A personal WSL machine built on the shared baseline";
        };

        home = {
          path = ./templates/home;
          description = "A personal WSL home environment, for a distro that is not NixOS";
        };
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

      # The opt-in path, built too: an escape hatch nobody tests is an escape
      # hatch that has already rotted.
      nixosConfigurations.example-home-manager = self.lib.mkWsl {
        hostName = "wsl-example-hm";
        user = {
          name = "dev";
          fullName = "Example Developer";
          email = "dev@example.com";
        };
        extraModules = [
          self.nixosModules.home-manager
          { company.home.modules = [ { programs.zsh.enable = true; } ]; }
        ];
      };

      # The non-NixOS tier, built too. GitHub's runners are Ubuntu, so CI
      # exercises this one on the kind of machine it is actually for.
      homeConfigurations.example = self.lib.mkWslHome {
        user = {
          name = "dev";
          fullName = "Example Developer";
          email = "dev@example.com";
        };
      };

      checks.${system} = {
        example = self.nixosConfigurations.example.config.system.build.toplevel;
        example-home-manager =
          self.nixosConfigurations.example-home-manager.config.system.build.toplevel;
        example-home = self.homeConfigurations.example.activationPackage;
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixpkgs-fmt;
    };
}
