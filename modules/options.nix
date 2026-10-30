# The option declarations both tiers share, and nothing else: no `config`, no
# NixOS, no home-manager. ./nixos and ./home each implement these in their own
# terms, so `company.user.email` means the same thing to a colleague whether
# their machine is NixOS-WSL or an ordinary distro with Nix on top, and the
# README documents one set of names rather than two.
#
# Options only one tier can honour stay declared in that tier, and the module
# system merges those declarations with these: company.user.extraGroups,
# company.nix.trustUser, company.docker.enable and company.network.windowsDns
# are all NixOS-only.
{ lib, ... }:

{
  options.company = {
    user = {
      name = lib.mkOption {
        type = lib.types.str;
        example = "anna";
        description = "Login name. On NixOS-WSL it also becomes wsl.defaultUser.";
      };

      fullName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Used for git's user.name. Omitted from git config when empty.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Used for git's user.email. Omitted from git config when empty.";
      };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Extras for this one machine. Anything a project needs belongs in that
        project's devenv.nix instead, so it travels with the repository and not
        with the machine.
      '';
    };

    nix = {
      extraSubstituters = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "https://company.cachix.org" ];
        description = "Binary caches on top of cache.nixos.org and devenv's.";
      };

      extraTrustedPublicKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Signing keys for extraSubstituters.";
      };
    };

    network = {
      caCertificates = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        example = lib.literalExpression "[ ./certs/company-root-ca.pem ]";
        description = ''
          Extra root CAs, for a TLS-inspecting proxy or internal services.
          NixOS adds them to the system bundle; the home tier can only point
          the user's own tools at a bundle it builds, since /etc is not
          its to write.
        '';
      };

      proxy = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "http://proxy.company.internal:8080";
        description = "HTTP(S) proxy. null means none.";
      };

      noProxy = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1,localhost,.internal";
        description = "Hosts that bypass company.network.proxy.";
      };
    };
  };
}
