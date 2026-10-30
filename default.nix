# The non-flake entry point. Flakes are the default and supported way in; this
# exists so a machine that cannot or does not want to enable them is not shut
# out -- `nixos-rebuild -f . -A nixosConfigurations.<name>` and a plain
# `imports = [ ... ]` in /etc/nixos/configuration.nix both work. See
# "Without flakes" in the README.
#
# flake-compat reads flake.lock and resolves the inputs itself, in ordinary
# Nix with no experimental features, so a consumer here still gets the exact
# nixpkgs, home-manager and nixos-wsl that CI tested rather than whatever a
# channel moved to. NixOS-WSL ships the same shim for the same reason.
#
# The flake-compat revision is looked up through the root node's inputs rather
# than as lock.nodes.flake-compat, because nixos-wsl has a flake-compat of its
# own and the plain name in a flat nodes map is not guaranteed to be ours.
(import
  (
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      node = lock.nodes.${lock.nodes.${lock.root}.inputs.flake-compat};
    in
    fetchTarball {
      url = "https://github.com/edolstra/flake-compat/archive/${node.locked.rev}.tar.gz";
      sha256 = node.locked.narHash;
    }
  )
  {
    src = ./.;
  }).defaultNix
