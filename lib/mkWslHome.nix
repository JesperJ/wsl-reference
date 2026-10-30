# The mirror of ./mkWsl.nix for a WSL distro that is not NixOS: a thin wrapper
# over homeModules.default that only turns arguments into `company.*` options.
# Anything it does not expose is still reachable through extraModules.
#
# There is no hostName here, and no docker, CA store or trusted-users: those
# belong to a system this tier does not have. See the README.
{ nixpkgs, home-manager, self }:

{ user                      # { name; fullName ? ""; email ? ""; }
, system ? "x86_64-linux"
, stateVersion ? "26.05"    # set once at install, never bump it afterwards
, extraModules ? [ ]
}:

home-manager.lib.homeManagerConfiguration {
  # Instantiated rather than taken from legacyPackages, so this tier agrees
  # with the NixOS one about allowUnfree.
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  modules = [
    self.homeModules.default
    {
      company.user = user;
      home = {
        username = user.name;
        homeDirectory = "/home/${user.name}";
        inherit stateVersion;
      };
    }
  ] ++ extraModules;
}
