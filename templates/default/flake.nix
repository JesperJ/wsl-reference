{
  description = "My WSL machine";

  # Pin a release tag so the baseline only changes when you bump it:
  #   edit the ref, then `nix flake update wsl-base`.
  inputs.wsl-base.url = "github:JesperJ/wsl-reference/v0.2.0";

  outputs = { wsl-base, ... }: {
    nixosConfigurations.wsl = wsl-base.lib.mkWsl {
      hostName = "WSL-CHANGEME";
      user = {
        name = "changeme";
        fullName = "Change Me";
        email = "change.me@company.com";
      };

      # Everything below is optional. Project tooling does NOT go here -- it
      # goes in that project's devenv.nix.
      extraModules = [
        # Declarative dotfiles, if you want them. The baseline leaves $HOME
        # alone, so `git config --global` and hand-edits to ~/.bashrc keep
        # working; uncomment these two to hand it to home-manager instead.
        # wsl-base.nixosModules.home-manager
        # { company.home.modules = [ ./home.nix ]; }

        ({ pkgs, ... }: {
          # company.extraPackages = [ pkgs.k9s ];
        })
      ];
    };
  };
}
