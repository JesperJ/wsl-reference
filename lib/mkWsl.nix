# A thin wrapper over nixosModules.wsl-dev. It only turns arguments into
# `company.*` options -- anything it does not expose is still reachable through
# `extraModules`, which is the point: the function is a convenience, the
# module is the interface.
{ nixpkgs, self }:

{ hostName
, user                      # { name; fullName ? ""; email ? ""; extraGroups ? [ ]; }
, stateVersion ? "26.05"    # set once at install, never bump it afterwards
, extraModules ? [ ]
}:

nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    self.nixosModules.wsl-dev
    {
      networking.hostName = hostName;
      company.user = user;
      system.stateVersion = stateVersion;
    }
  ] ++ extraModules;
}
