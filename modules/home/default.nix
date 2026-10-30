# The dotfiles tier: the user's own environment, and nothing that needs a
# system. This is what the NixOS opt-in bridge layers on top of a machine that
# already has direnv and a git identity of its own; ./standalone.nix adds the
# rest for a distro that is not NixOS.
#
# Shell taste is personal and is added through company.home.modules, not here.
{ ... }:

{
  imports = [
    ../options.nix
    ./git.nix
  ];

  config = {
    programs.home-manager.enable = true;

    # bash, because it is what WSL starts regardless of the login shell. A
    # person who wants zsh enables it in their own module.
    programs.bash.enable = true;

    # The bridge to every project: entering a directory with a .envrc that
    # says `use devenv` loads its shell. nix-direnv caches the evaluation so
    # that is instant after the first time. On NixOS the system already does
    # this and the bridge switches this copy off, so the hook is not sourced
    # twice.
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      config.global.hide_env_diff = true;
    };
  };
}
