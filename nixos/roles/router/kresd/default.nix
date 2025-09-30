{
  lib,
  config,
  pkgs,
  ...
}:
let
  fclib = config.fclib;
  role = config.flyingcircus.roles.router;
in
lib.mkIf role.enable {
  # set by upstream kresd module
  networking.resolvconf.useLocalResolver = fclib.mkPlatform false;

  services.kresd = {
    enable = true;
    package = pkgs.knot-resolver.override { extraFeatures = true; };
    listenPlain = [
      "0.0.0.0:53"
      "[::]:53"
    ];
    extraConfig = ''
      -- basic config

      modules = {
        'serve_stale < cache',
        'hints > iterate',
        'prefill',
        'view'
      }

      cache.size = 1024*MB

    ''
    + lib.optionalString (role.sourceAddressV4 != null) ''
      net.outgoing_v4('${role.sourceAddressV4}')
    ''
    + lib.optionalString (role.sourceAddressV6 != null) ''
      net.outgoing_v6('${role.sourceAddressV6}')
    ''
    + ''

      -- resilience: prefill the root zone data
      prefill.config({
          ['.'] = {
              url = 'https://www.internic.net/domain/root.zone',
              interval = 86400,
              ca_file = '/etc/pki/tls/certs/ca-bundle.crt',
          }
      })

      -- resilience: prefer serving stale data over not serving at all.
      -- rfc8767 recommends a stale serving timeout of 1800s with a client
      -- query timeout of 2s. however, kresd has a minimum granularity of
      -- 2s (KR_CONN_RTT_MAX), so we need to configure a higher client query
      -- timeout than recommended in the rfc to ensure that clients wait for
      -- long enough to trigger the stale serving behaviour. we match the
      -- rfc for the stale serving timeout though so we get the benefits
      -- if the granularity changes in the future.
      serve_stale.timeout = 1800

      -- if a backend is detected as down, let it stay down for a minute so we
      -- can immediately respond to requests. however, this also means backends
      -- may take a minute to recover
      cache.ns_tout(60000)

      -- access control: only answer queries from ourselves and own address
      -- space
      view:addr('127.0.0.0/8', policy.all(policy.PASS))
      view:addr('::1/128', policy.all(policy.PASS))

      ${lib.concatMapStringsSep "\n" (
        net: "view:addr('${net}', policy.all(policy.PASS))"
      ) fclib.networks.all}

      view:addr('0.0.0.0/0', policy.all(policy.DROP))
      view:addr('::/0', policy.all(policy.DROP))

      -- load a hosts file for our assignments out of rfc1918 address space in
      -- order to synthesise PTR records for reverse dns. don't synthesise
      -- nodata responses for queries with mismatching address type (i.e.
      -- resolve AAAA records using public dns for names which only have an
      -- ipv4 address in the hosts file).
      hints.add_hosts('/etc/nixos/rfc1918-hosts')
      hints.use_nodata(false)

      --[[
        Operator's note: control forwarders by setting

           flyingcircus.roles.router.dnsForwarders = lib.mkForce [ ... ];

        in the NixOS configuration. Leave the list empty to disable
        forwarding entirely.
      ]]

      ${
        if (role.dnsForwarders != [ ]) then
          let
            forwarderLiteral = lib.concatMapStringsSep ", " (f: "'${f}'") role.dnsForwarders;
          in
          ''
            -- forward queries to upstream resolvers
            policy.add(policy.all(policy.FORWARD({${forwarderLiteral}})))
          ''
        else
          ''
            -- the policy module is compliant with rfc6303 by default, override
            -- these defaults to accept queries for rfc1918 reverse zones by the
            -- hints module
            policy.add(
              policy.suffix(
                policy.PASS,
                policy.todnames({
                  '10.in-addr.arpa.',
                  '16.172.in-addr.arpa.',
                  '17.172.in-addr.arpa.',
                  '18.172.in-addr.arpa.',
                  '19.172.in-addr.arpa.',
                  '20.172.in-addr.arpa.',
                  '21.172.in-addr.arpa.',
                  '22.172.in-addr.arpa.',
                  '23.172.in-addr.arpa.',
                  '24.172.in-addr.arpa.',
                  '25.172.in-addr.arpa.',
                  '26.172.in-addr.arpa.',
                  '27.172.in-addr.arpa.',
                  '28.172.in-addr.arpa.',
                  '29.172.in-addr.arpa.',
                  '30.172.in-addr.arpa.',
                  '31.172.in-addr.arpa.',
                  '168.192.in-addr.arpa.'
                })
              )
            )
          ''
      }
    '';
  };

}
