{
  description = "My WSL home environment";

  # For a WSL distro that is not NixOS. Pin a release tag so the baseline only
  # changes when you bump it: edit the ref, then `nix flake update wsl-base`.
  inputs.wsl-base.url = "github:JesperJ/wsl-reference/v0.2.0";

  outputs = { wsl-base, ... }: {
    # Name this after your login name: home-manager looks up
    # homeConfigurations.<name> and the build asserts it owns $HOME.
    #   nix run home-manager/release-26.05 -- switch --flake .#changeme
    # and afterwards just `home-manager switch --flake .#changeme`.
    homeConfigurations.changeme = wsl-base.lib.mkWslHome {
      user = {
        name = "changeme";
        fullName = "Change Me";
        email = "change.me@company.com";
      };

      # Everything below is optional. Project tooling does NOT go here -- it
      # goes in that project's devenv.nix.
      extraModules = [
        ({ pkgs, ... }: {
          # company.extraPackages = [ pkgs.k9s ];
          # programs.zsh.enable = true;
        })
      ];
    };
  };
}
