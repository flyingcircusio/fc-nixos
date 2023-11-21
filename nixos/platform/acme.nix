{ config, pkgs, lib, ... }:
let
  inherit (config) fclib;
in
{
  # Generate a sensu check for each acme cert to check its validity and warn
  # when it expires.
  flyingcircus.services.sensu-client.checks =
    lib.listToAttrs
      (map (n: lib.nameValuePair "ssl_cert_acme_${n}" {
        notification = "ACME (Letsencrypt) certificate for ${n} is invalid or will expire soon";
        command = "check_http -p 443 -S --sni -C 25,14 -H ${n}";
        interval = 600;
      })
      (lib.attrNames config.security.acme.certs));

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
    lib.listToAttrs
      (map (n: lib.nameValuePair "acme-${n}" {
        inherit serviceConfig unitConfig;
        # Upstream added the renewal service to multi-user.target which means that
        # every fc-manage run triggers a renewal. We want that the renewal is
        # only triggered by the timer.
        wantedBy = lib.mkForce [];
      })
      (lib.attrNames config.security.acme.certs));

    # fallback ACME settings
    security.acme.acceptTerms = true;
    security.acme.defaults.email = "admin@flyingcircus.io";
}
