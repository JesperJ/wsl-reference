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
      The starship prompt in every interactive bash: the directory, the git
      branch and state, the active devenv shell, the .NET SDK. A person
      changes it with their own ~/.config/starship.toml, which takes over
      from the system default as soon as it exists; set this to false to go
      back to the plain bash prompt.
    '';
  };

  # NixOS's own module hooks starship into /etc's interactive bash init and
  # skips the system settings when ~/.config/starship.toml (or
  # $STARSHIP_CONFIG) exists.
  config.programs.starship.enable = config.company.shell.starship.enable;
}
