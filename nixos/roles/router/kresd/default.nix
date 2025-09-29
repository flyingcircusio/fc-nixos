{
  lib,
  config,
  pkgs,
  ...
}:
let
  role = config.flyingcircus.roles.router;
in
{

  services.kresd = {
    enable = true;
    package = pkgs.knot-resolver.override { extraFeatures = true; };
    listenPlain = [ "172.20.3.1:53" ];
    listenTLS = [ ];
    listenDoH = [ ];
    extraConfig = ''
      modules = {
        'serve_stale < cache',
        'prefill'
      }

      log_level('debug')

      cache.size = 1024*MB

    ''
    + lib.optionalString (role.sourceAddressV4 != null) ''
      net.outgoing_v4('${role.sourceAddressV4}')
    ''
    + lib.optionalString (role.sourceAddressV6 != null) ''
      net.outgoing_v6('${role.sourceAddressV6}')
    ''
    + ''

      -- resiliency: get root zone data
      prefill.config({
          ['.'] = {
              url = 'https://www.internic.net/domain/root.zone',
              interval = 86400, -- seconds
              ca_file = '/etc/pki/tls/certs/ca-bundle.crt', -- optional
          }
      })

      -- resiliency: prefer serving stale over not serving at all

      -- serve stale responses if we do not receive an answer quickly
      -- however, the granularity here is 2s (KR_CONN_RTT_MAX) so
      -- the clients must have a higher timeout because our 1800
      -- timeout will only trigger after 2s. I'm putting the ideal number
      -- in here so we can profit if the granularity changes in the future.
      serve_stale.timeout = 1800; -- rfc8767 recommendation in correspondence with 2s timeouts for our clients.

      -- if a backend is detected as down, let it stay down for a minute so we
      -- can immediately respond to requests. however, this also means backends
      -- may take a minute to recover
      cache.ns_tout(30000)

      modules.unload('refuse_nord')

      --[[
        Operator's note: control forwarders by setting

           flyingcircus.roles.router.dnsForwarders = lib.mkForce [ ... ];

        in the NixOS configuration. Leave the list empty to disable
        forwarding entirely.
      ]]

      --[[
      ${lib.optionalString (role.dnsForwarders != [ ]) (
        # align the indentation with the rest of the file
        let
          text = ''
            policy.add(
              policy.all(
                policy.FORWARD({
                  ${lib.concatMapStringsSep ",\n  " (a: "'${a}'") role.dnsForwarders}
                 })
              )
            )
          '';
          lines = lib.splitString "\n" text;
        in
        lib.concatMapStringsSep "\n" (a: "  ${a}") lines
      )}
       ]]

    '';
  };

}
