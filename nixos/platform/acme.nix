{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config) fclib;
  checkCert = pkgs.writeShellScript "check-local-acme-cert" ''
    certificate_path="$1"
    critical_sec=$((14 * 24 * 3600))
    warning_sec=$((25 * 24 * 3600))

    openssl x509 -in "$certificate_path" -noout -enddate

    if ! openssl x509 -checkend $critical_sec -noout -in "$certificate_path" > /dev/null
    then
        exit 2
    fi

    if ! openssl x509 -checkend $warning_sec -noout -in "$certificate_path" > /dev/null
    then
        exit 1
    fi
  '';

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
        command = "/run/wrappers/bin/sudo ${checkCert} ${cert.directory}/fullchain.pem";
        interval = 3600;
      }
    ) config.security.acme.certs;

    systemd.services =
      let
        # Retry certificate renewal 30s after a failure.
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = fclib.mkPlatformOverride 30;
        };

        # Allow 3 retries/starts per hour to not hit the rate limit
        # of 5 per hour so we have two left to try manually.
        unitConfig = {
          StartLimitIntervalSec = "1h";
          StartLimitBurst = 3;
        };
      in
      lib.listToAttrs (
        map (
          n:
          lib.nameValuePair "acme-${n}" {
            inherit serviceConfig unitConfig;
            # Upstream added the renewal service to multi-user.target which means that
            # every fc-manage run triggers a renewal. We want that the renewal is
            # only triggered by the timer.
            wantedBy = lib.mkForce [ ];
          }
        ) (lib.attrNames config.security.acme.certs)
      );

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
