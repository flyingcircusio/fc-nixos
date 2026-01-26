{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) fclib;
  checkCert = "${pkgs.fc.check-tls-cert}/bin/check_tls_cert";
in
lib.mkMerge [
  {
    flyingcircus.passwordlessSudoRules = [
      {
        commands = [ "${checkCert}" ];
        groups = [ "sensuclient" ];
      }
    ];

    # Generate a sensu check for each acme cert to check its validity and warn
    # when it expires.

    flyingcircus.services.sensu-client.checks = lib.mapAttrs' (
      n: cert:
      lib.nameValuePair "ssl_cert_acme_${n}" {
        notification = "ACME (Letsencrypt) certificate for ${n} is invalid or will expire soon";
        command = "sudo ${checkCert} ${cert.directory}/fullchain.pem ${n}";
        interval = 3600;
      }
    ) config.security.acme.certs;

    # fallback ACME settings
    security.acme.acceptTerms = true;
    security.acme.defaults.email = "admin@flyingcircus.io";
  }

  # Machines set up with 24.05 or earlier need to use the ACME account hash
  # generation of <= NixOS 23.11 to avoid forced
  # re-registration, see https://github.com/NixOS/nixpkgs/issues/316608
  (lib.mkIf (lib.versionOlder config.system.stateVersion "24.11") {
    security.acme.defaults.server = fclib.mkPlatform null;
  })
]
