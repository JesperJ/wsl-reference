# The baseline. Every file here only declares `company.*` options and maps them
# onto upstream ones; nothing is switched on by being imported except what
# every WSL dev box needs to be usable at all.
#
# No home-manager: on a single-user WSL box everything the baseline needs from
# it -- direnv and a git identity -- is a plain NixOS option, and managing
# $HOME from the store would break `git config --global` and hand-edits to
# ~/.bashrc for people who never asked for a dotfile manager. Anyone who does
# want it adds `wsl-base.nixosModules.home-manager` to extraModules.
{
  imports = [
    ./user.nix
    ./nix.nix
    ./dev.nix
    ./git.nix
    ./network.nix
  ];
}
