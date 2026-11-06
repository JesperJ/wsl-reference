# The interactive shell a person meets on first login. A default, not a
# policy: everything here is either theirs to override in their own config
# file, or one option to switch off.
#
# Done at system level on purpose, not through home-manager: the baseline
# leaves $HOME alone (see ./default.nix), so this must not need a managed
# ~/.bashrc to work.
{ config, lib, ... }:

{
  options.company.shell.starship.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      The starship prompt in every interactive bash. How it looks lives in
      ~/.config/starship.toml, which bootstrap.ps1 writes once with a
      commented starting point and never touches again; set this to false
      to go back to the plain bash prompt.
    '';
  };

  # NixOS's own module hooks starship into /etc's interactive bash init. No
  # settings here on purpose: the look is the user's file in $HOME, and
  # without one starship uses its own defaults.
  config.programs.starship.enable = config.company.shell.starship.enable;
}
