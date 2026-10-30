# The corporate network at user level. ../nixos/network.nix puts the CAs in
# the system bundle and the proxy in nix-daemon's environment; neither is the
# user's to write here, so this does what it can from $HOME and the README
# says what is left over.
{ config, lib, pkgs, ... }:

let
  cfg = config.company.network;

  # One bundle: the usual roots plus the company's, because pointing
  # SSL_CERT_FILE at the extra CAs alone would make every public host fail.
  bundle = pkgs.runCommand "company-ca-bundle.crt" { } ''
    cat ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt \
      ${lib.concatMapStringsSep " " (c: "${c}") cfg.caCertificates} > $out
  '';
in
{
  config = lib.mkMerge [
    (lib.mkIf (cfg.caCertificates != [ ]) {
      # Covers the tools in this profile and nix run as this user. It does NOT
      # cover the nix daemon, which is what fetches for a multi-user install
      # and reads its own environment, nor anything the distro installed; both
      # need the root-side step in the README.
      home.sessionVariables = {
        SSL_CERT_FILE = "${bundle}";
        NIX_SSL_CERT_FILE = "${bundle}";
        GIT_SSL_CAINFO = "${bundle}";
        CURL_CA_BUNDLE = "${bundle}";
      };
    })

    (lib.mkIf (cfg.proxy != null) {
      # Both cases, because tools disagree about which they read.
      home.sessionVariables = {
        http_proxy = cfg.proxy;
        https_proxy = cfg.proxy;
        HTTP_PROXY = cfg.proxy;
        HTTPS_PROXY = cfg.proxy;
        no_proxy = cfg.noProxy;
        NO_PROXY = cfg.noProxy;
      };
    })
  ];
}
