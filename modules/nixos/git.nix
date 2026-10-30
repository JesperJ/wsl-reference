# git, configured machine-wide rather than through a dotfile manager. A WSL
# distro has exactly one user (see user.nix), so /etc/gitconfig is the right
# scope for their identity: written once from company.user.*, and still
# overridable the ordinary way, because `git config --global` writes to the
# user's own file and nothing here manages that file.
{ config, lib, ... }:

let
  cfg = config.company.user;

  # Empty identity fields are omitted rather than written as "": git then
  # prompts on the first commit, which beats committing as nobody.
  identity = lib.filterAttrs (_: v: v != "") {
    name = cfg.fullName;
    email = cfg.email;
  };
in
{
  config = {
    programs.git = {
      enable = true;
      config = {
        init.defaultBranch = "main";
        pull.rebase = true;
        # Windows checkouts and WSL checkouts of the same repo disagree on
        # line endings without this.
        core.autocrlf = "input";
      } // lib.optionalAttrs (identity != { }) { user = identity; };
    };
  };
}
