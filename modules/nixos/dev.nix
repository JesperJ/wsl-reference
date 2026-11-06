# What every project's devenv shell assumes the machine already has.
# company.extraPackages is declared in ../options.nix; docker.enable is
# declared here, because a home-manager tier cannot install a daemon.
{ config, lib, pkgs, devenvTemplates, devenvPackage, ... }:

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
  options.company.docker.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Native Docker inside the distro, for devenv containers and VS Code dev containers.";
  };

  config = lib.mkMerge [
    {
      # git is not listed here: ./git.nix enables programs.git, which installs
      # the package along with /etc/gitconfig. devenv is not nixpkgs' copy but
      # the release pinned in the flake's own devenv input.
      environment.systemPackages = with pkgs; [
        devenvPackage
        devenvify
        curl
        wget
        vim
        file
        unzip
      ] ++ cfg.extraPackages;

      # The bridge to every project: entering a directory whose .envrc says
      # `use devenv` loads that project's shell. The NixOS module installs
      # direnv, sources the hook into interactive shells and enables
      # nix-direnv, whose cache makes that instant after the first time.
      programs.direnv = {
        enable = true;
        settings.global.hide_env_diff = true;
      };

      # VS Code Remote - WSL downloads a generic Linux node server and extension
      # binaries that NixOS' stub-ld refuses to start; nix-ld runs them.
      programs.nix-ld.enable = true;

      # `code .` from the shell runs a Windows .exe, which needs WSL's
      # WSLInterop binfmt handler. WSL registers it at start, but with systemd
      # the binfmt_misc filesystem is mounted afresh and the entry is gone, so
      # every .exe fails with "Exec format error". Registering it from NixOS
      # puts it back on every boot. mkDefault: a machine can still opt out.
      wsl.interop.register = lib.mkDefault true;
    }

    (lib.mkIf cfg.docker.enable {
      virtualisation.docker.enable = true;
      users.users.${cfg.user.name}.extraGroups = [ "docker" ];
    })
  ];
}
