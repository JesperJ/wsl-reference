# The corporate network: the things that break first on a work machine and are
# the same for everyone, so they are set here once rather than per person.
{ config, lib, ... }:

let
  cfg = config.company.network;
in
{
  options.company.network = {
    caCertificates = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = lib.literalExpression "[ ./certs/company-root-ca.pem ]";
      description = ''
        Extra root CAs, for a TLS-inspecting proxy or internal services. Added
        to the system bundle, which Nix, git, curl and most tools in a devenv
        shell read via NIX_SSL_CERT_FILE / SSL_CERT_FILE.
      '';
    };

    proxy = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://proxy.company.internal:8080";
      description = "HTTP(S) proxy for the shell and for the nix daemon. null means none.";
    };

    noProxy = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1,localhost,.internal";
      description = "Hosts that bypass company.network.proxy.";
    };

    windowsDns = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let WSL generate /etc/resolv.conf from Windows. Corporate VPN DNS
        usually only works this way; turning it off means managing DNS here.
      '';
    };
  };

  config = lib.mkMerge [
    { security.pki.certificateFiles = cfg.caCertificates; }

    # networking.proxy also reaches nix-daemon's environment, which is what
    # actually fetches; setting it only in the shell is not enough.
    (lib.mkIf (cfg.proxy != null) {
      networking.proxy = {
        default = cfg.proxy;
        noProxy = cfg.noProxy;
      };
    })

    (lib.mkIf cfg.windowsDns {
      wsl.wslConf.network.generateResolvConf = true;
      # resolvconf fights the file WSL writes.
      networking.resolvconf.enable = false;
    })
  ];
}
