# git at user level, from the same company.user.* that /etc/gitconfig is built
# from on NixOS. Both can be active at once -- a user-level file wins over
# /etc, and the values are identical -- so the overlap is duplication rather
# than conflict.
{ config, lib, ... }:

let
  cfg = config.company.user;
in
{
  config = {
    programs.git = {
      enable = true;
      settings = {
        # Empty identity fields are omitted: git then prompts on the first
        # commit, which beats committing as "".
        user = lib.filterAttrs (_: v: v != "") {
          name = cfg.fullName;
          email = cfg.email;
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
