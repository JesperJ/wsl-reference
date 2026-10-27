{
  description = "My WSL machine";

  # Pin a release tag so the baseline only changes when you bump it:
  #   edit the ref, then `nix flake update wsl-base`.
  # While the baseline still lives inside nixos-config, the URL is
  #   git+https://github.com/JesperJ/nixos-config?dir=wsl-reference&ref=<tag>
  inputs.wsl-base.url = "github:YOUR-ORG/wsl-reference/v0.1.0";

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
        ({ pkgs, ... }: {
          # company.extraPackages = [ pkgs.k9s ];
          # company.home.modules = [ ./home.nix ];
        })
      ];
    };
  };
}
