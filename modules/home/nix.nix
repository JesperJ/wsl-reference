# Nix settings a user can set for themselves, mirroring ../nixos/nix.nix.
#
# Two limits are worth knowing, and neither has a workaround at this level:
# trusted-users cannot be granted here at all -- Nix only reads it from root's
# /etc/nix/nix.conf, by design, since a user granting themselves trust would
# be no restriction -- and the caches below are only honoured once the user IS
# trusted. Until that one root-side step is done, devenv will build what a
# cache already has.
{ config, lib, pkgs, ... }:

let
  cfg = config.company.nix;
in
{
  config = {
    # Only to validate the nix.conf this generates at build time, and to give
    # the gc timer a nix-collect-garbage to run. It is not added to the
    # profile, so it cannot shadow the nix the distro installed or skew
    # against its daemon.
    nix.package = pkgs.nix;

    # extra-* rather than the plain keys: this file is layered on top of the
    # machine's /etc/nix/nix.conf, and replacing its substituters would drop
    # cache.nixos.org.
    nix.settings = {
      extra-substituters = [ "https://devenv.cachix.org" ] ++ cfg.extraSubstituters;
      extra-trusted-public-keys = [
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      ] ++ cfg.extraTrustedPublicKeys;
    };

    # A systemd *user* timer, so the distro needs systemd enabled in
    # /etc/wsl.conf -- recent Ubuntu images do by default. Persistent, so a run
    # missed while Windows was off fires on the next start. It collects only
    # this user's profiles; the system profile is root's to prune.
    nix.gc = {
      automatic = true;
      dates = "weekly";
      persistent = true;
      options = "--delete-older-than 30d";
    };
  };
}
