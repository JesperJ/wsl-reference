# home-manager, wired as a NixOS module so one `nixos-rebuild switch` updates
# both halves. The home baseline lives in ../home; a person adds their own
# dotfiles through company.home.modules.
{ config, lib, ... }:

let
  cfg = config.company;
in
{
  options.company.home.modules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    example = lib.literalExpression ''
      [ ({ pkgs, ... }: { programs.zsh.enable = true; home.packages = [ pkgs.k9s ]; }) ]
    '';
    description = "Extra home-manager modules for the user, layered over the baseline.";
  };

  config = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      users.${cfg.user.name} = {
        imports = [ ../home ] ++ cfg.home.modules;

        # Copied in rather than read from NixOS config, so ../home stays a
        # plain home-manager module usable without NixOS too.
        company.home.git = { inherit (cfg.user) fullName email; };

        home.stateVersion = config.system.stateVersion;
      };
    };
  };
}
