# The one person this machine belongs to. A WSL distro has exactly one user --
# wsl.defaultUser takes a single name -- so this is a single submodule, not a
# list of members.
{ config, lib, ... }:

let
  cfg = config.company.user;
in
{
  options.company.user = {
    name = lib.mkOption {
      type = lib.types.str;
      example = "anna";
      description = "Login name. Becomes wsl.defaultUser and the home-manager user.";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Used for git's user.name. Omitted from git config when empty.";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Used for git's user.email. Omitted from git config when empty.";
    };

    sshKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Public keys allowed to log in, only relevant with company.sshServer.enable.";
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Groups beyond the ones the baseline grants (wheel, docker).";
    };
  };

  config = {
    wsl.enable = true;
    wsl.defaultUser = cfg.name;

    # nixos-wsl already creates the account as a normal user in `wheel` and
    # sets wheelNeedsPassword = false. That is deliberate and kept: on WSL,
    # `wsl -u root` from Windows is root without PAM, so a sudo password stops
    # nobody who can run wsl.exe and only locks out the owner, whose account
    # has no password. The Windows login is the real boundary here.
    users.users.${cfg.name} = {
      extraGroups = cfg.extraGroups;
      openssh.authorizedKeys.keys = cfg.sshKeys;
    };
  };
}
