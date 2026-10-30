# The one person this machine belongs to. A WSL distro has exactly one user --
# wsl.defaultUser takes a single name -- so this is a single submodule, not a
# list of members. The identity fields themselves are declared in
# ../options.nix, because the home tier needs the same names.
#
# No sshKeys option: there is no sshd here. WSL2 sits behind NAT, so reaching
# it needs mirrored networking or a netsh portproxy on the Windows side, and
# anyone who can run wsl.exe already has a root shell without authenticating.
# A machine nobody logs into over the network needs no authorized_keys. Should
# one ever want it, extraModules can set services.openssh and
# users.users.<name>.openssh.authorizedKeys.keys directly.
{ config, lib, ... }:

let
  cfg = config.company.user;
in
{
  options.company.user.extraGroups = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Groups beyond the ones the baseline grants (wheel, docker).";
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
    };
  };
}
