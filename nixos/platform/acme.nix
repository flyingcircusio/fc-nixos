{ config, pkgs, lib, ... }:
{
  systemd.services =
  let
    # Retry certificate renewal 30s after a failure.
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 30;
    };

    # Allow 5 retries/starts per day.
    unitConfig = {
      StartLimitIntervalSec = "24h";
      StartLimitBurst = 5;
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
    security.acme.email = "admin@flyingcircus.io";
}
