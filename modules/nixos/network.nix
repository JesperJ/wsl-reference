# The corporate network: the things that break first on a work machine and are
# the same for everyone, so they are set here once rather than per person. The
# CA, proxy and noProxy options are declared in ../options.nix, which the home
# tier shares; windowsDns is declared here, because only a system writes
# /etc/wsl.conf.
{ config, lib, ... }:

let
  cfg = config.company.network;
in
{
  options.company.network.windowsDns = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Let WSL generate /etc/resolv.conf from Windows. Corporate VPN DNS
      usually only works this way; turning it off means managing DNS here.
    '';
  };

  config = lib.mkMerge [
    # The system bundle, which Nix, git, curl and most tools in a devenv shell
    # read via NIX_SSL_CERT_FILE / SSL_CERT_FILE.
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
