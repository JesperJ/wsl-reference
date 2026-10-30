# The opt-in bridge to home-manager, for someone who wants their dotfiles
# declared too.
#
# Deliberately NOT part of nixosModules.default. A single-user WSL box gets
# everything the baseline needs from plain NixOS options -- direnv from
# dev.nix, a git identity in /etc/gitconfig from git.nix -- and managing $HOME
# from the store costs more than it pays there: a store-symlinked
# ~/.config/git/config makes `git config --global` fail, and a generated
# ~/.bashrc reverts hand-edits on the next switch. That is a fine trade for
# someone who chose it and a bad surprise for someone who did not, so it is
# asked for rather than assumed:
#
#   extraModules = [
#     wsl-base.nixosModules.home-manager
#     { company.home.modules = [ ./home.nix ]; }
#   ];
#
# Wired as a NixOS module so one `nixos-rebuild switch` still updates both
# halves. The home baseline lives in ./home.
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
        imports = [ ./home ] ++ cfg.home.modules;

        # Copied in rather than read from NixOS config, so ./home stays a
        # plain home-manager module usable without NixOS too -- which is what
        # makes it the delivery path for a non-NixOS WSL distro. It writes the
        # same identity /etc/gitconfig already carries; a user-level file wins
        # over /etc, so the overlap is duplication, not conflict.
        company.home.git = { inherit (cfg.user) fullName email; };

        # dev.nix already sources the direnv hook from /etc, and two hooks mean
        # two runs per prompt, so the home baseline's copy is switched off
        # here. Its git config is left alone instead: that is a file, not a
        # hook, and the user-level one simply wins over /etc -- someone opting
        # in probably wants home-manager to own it so they can add aliases.
        programs.direnv.enable = lib.mkForce false;

        home.stateVersion = config.system.stateVersion;
      };
    };
  };
}
