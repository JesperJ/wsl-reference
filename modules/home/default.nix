# The user's environment: just enough that a project's devenv shell activates
# on `cd` and git commits carry the right name. Shell taste is personal and is
# added through company.home.modules, not here.
{ config, lib, ... }:

let
  cfg = config.company.home;
in
{
  options.company.home.git = {
    fullName = lib.mkOption { type = lib.types.str; default = ""; };
    email = lib.mkOption { type = lib.types.str; default = ""; };
  };

  config = {
    programs.home-manager.enable = true;

    # bash, because it is what WSL starts regardless of the login shell. A
    # person who wants zsh enables it in their own module.
    programs.bash.enable = true;

    # The bridge to every project: entering a directory with a .envrc that
    # says `use devenv` loads its shell. nix-direnv caches the evaluation so
    # that is instant after the first time.
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
      config.global.hide_env_diff = true;
    };

    programs.git = {
      enable = true;
      settings = {
        # Empty identity fields are omitted: git then prompts on the first
        # commit, which beats committing as "".
        user = lib.filterAttrs (_: v: v != "") {
          name = cfg.git.fullName;
          email = cfg.git.email;
        };
        init.defaultBranch = "main";
        pull.rebase = true;
        # Windows checkouts and WSL checkouts of the same repo disagree on
        # line endings without this.
        core.autocrlf = "input";
      };
    };
  };
}
