# What ../nixos/dev.nix provides system-wide, provided at user level instead.
# Only nix-ld has no counterpart, and needs none: a foreign distro has a real
# /lib64/ld-linux-x86-64.so.2 already, so VS Code's server runs unaided. Docker
# is the distro's to install.
{ config, lib, pkgs, devenvTemplates, devenvPackage, ... }:

let
  cfg = config.company;

  devenvify = pkgs.callPackage "${devenvTemplates}/package.nix" { };
in
{
  config = {
    # git is absent on purpose: ./git.nix enables programs.git, which installs
    # the package itself. devenv is the release pinned in the flake's own
    # devenv input, as in ../nixos/dev.nix.
    home.packages = with pkgs; [
      devenvPackage
      devenvify
      curl
      wget
      vim
      file
      unzip
    ] ++ cfg.extraPackages;
  };
}
