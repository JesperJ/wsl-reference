# The whole tier for a WSL distro that is not NixOS: Ubuntu or Debian with Nix
# installed, where there is no system configuration to put anything in. It
# layers the parts of ../nixos that a user can own onto ./default.nix.
#
# What it cannot do, because /etc is not the user's to write, is listed in the
# README under "A distro that is not NixOS" -- above all trusted-users, which
# Nix ignores in a user's nix.conf by design, so the per-project binary caches
# need one root-side step at install time or every project compiles what a
# cache already has.
{ ... }:

{
  imports = [
    ./default.nix
    ./dev.nix
    ./nix.nix
    ./network.nix
  ];

  config = {
    # Not NixOS: this sets NIX_PATH and XDG_DATA_DIRS the way the distro
    # expects, so installed packages' desktop files and man pages are found.
    targets.genericLinux.enable = true;
  };
}
