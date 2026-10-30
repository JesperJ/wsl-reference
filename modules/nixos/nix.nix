# Nix itself. The baseline's job is to make `cd project && direnv allow` work;
# the project's own devenv.nix decides what is in the shell. The cache options
# are declared in ../options.nix, which the home tier shares; trustUser is
# declared here, because only a system can grant it.
{ config, lib, ... }:

let
  cfg = config.company.nix;
in
{
  options.company.nix.trustUser = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Put the user in nix.settings.trusted-users. devenv reads binary caches
      from each project's devenv.yaml (`cachix.pull`), and Nix silently drops
      caches requested by an untrusted user, so without this every project
      compiles what its cache already has. trusted-users is root-equivalent,
      which on WSL grants nothing new (see user.nix on `wsl -u root`).
    '';
  };

  config = {
    nixpkgs.config.allowUnfree = true;

    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" ] ++ lib.optional cfg.trustUser config.company.user.name;
      substituters = [ "https://devenv.cachix.org" ] ++ cfg.extraSubstituters;
      trusted-public-keys = [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ] ++ cfg.extraTrustedPublicKeys;
    };

    # WSL has no bootloader, so there is no configurationLimit; prune by age
    # instead. The timer is Persistent, so a run missed while Windows was off
    # fires on the next start.
    nix.gc = {
      automatic = true;
      dates = "weekly";
      persistent = true;
      options = "--delete-older-than 30d";
    };
    nix.optimise.automatic = true;
  };
}
