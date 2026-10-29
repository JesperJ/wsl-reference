# What every project's devenv shell assumes the machine already has.
{ config, lib, pkgs, devenvTemplates, ... }:

let
  cfg = config.company;

  # devenvify copies one of the bundled devenv templates into a project, so a
  # new repository starts from the shell everyone else already has instead of
  # from `devenv init` and guesswork. The templates are baked into the
  # derivation, so no machine needs the templates repository checked out --
  # run `devenvify` with no arguments to list them.
  devenvify = pkgs.callPackage "${devenvTemplates}/package.nix" { };
in
{
  options.company = {
    docker.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Native Docker inside the distro, for devenv containers and VS Code dev containers.";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        System-wide extras for this one machine. Anything a project needs
        belongs in that project's devenv.nix instead, so it travels with the
        repository and not with the machine.
      '';
    };
  };

  config = lib.mkMerge [
    {
      environment.systemPackages = with pkgs; [
        devenv
        devenvify
        git
        curl
        wget
        vim
        file
        unzip
      ] ++ cfg.extraPackages;

      # VS Code Remote - WSL downloads a generic Linux node server and extension
      # binaries that NixOS' stub-ld refuses to start; nix-ld runs them.
      programs.nix-ld.enable = true;
    }

    (lib.mkIf cfg.docker.enable {
      virtualisation.docker.enable = true;
      users.users.${cfg.user.name}.extraGroups = [ "docker" ];
    })
  ];
}
