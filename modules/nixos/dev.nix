# What every project's devenv shell assumes the machine already has.
{ config, lib, pkgs, ... }:

let
  cfg = config.company;
in
{
  options.company = {
    docker.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Native Docker inside the distro, for devenv containers and VS Code dev containers.";
    };

    sshServer.enable = lib.mkEnableOption ''
      sshd on port 2222, key-only. Off by default: WSL2 sits behind NAT, so it
      is only reachable with mirrored networking in .wslconfig or a netsh
      portproxy, and 2222 avoids clashing with Windows' own sshd
    '';

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

    (lib.mkIf cfg.sshServer.enable {
      services.openssh = {
        enable = true;
        ports = [ 2222 ];
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };
    })
  ];
}
