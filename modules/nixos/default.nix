# The baseline. Every file here only declares `company.*` options and maps them
# onto upstream ones; nothing is switched on by being imported except what
# every WSL dev box needs to be usable at all.
{
  imports = [
    ./user.nix
    ./nix.nix
    ./dev.nix
    ./network.nix
    ./home.nix
  ];
}
