{ system ? builtins.currentSystem
, nixpkgs ? (import ../versions.nix {}).nixpkgs
, pkgs ? import ../. {}
}:

with import "${nixpkgs}/nixos/lib/testing.nix" { inherit system; };
with pkgs.lib;

let
  router =
    { config, pkgs, ... }:
    with pkgs.lib;
    let
      vlanIfs = range 1 (length config.virtualisation.vlans);
    in {
      environment.systemPackages = with pkgs; [ iptables curl ];
      virtualisation.vlans = [ 1 2 3 ];  # fe srv tr
      boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = true;
      networking = {
        useDHCP = false;
        firewall.allowPing = true;
        firewall.checkReversePath = true;
        interfaces = mkForce (listToAttrs (flip map vlanIfs (n:
          nameValuePair "eth${toString n}" {
            ipv4.addresses = [ { address = "10.55.${toString n}.1"; prefixLength = 24; } ];
            ipv6.addresses = [ { address = "2001:db8:${toString n}::1"; prefixLength = 64; } ];
          })));
      };
    };

  encInterfaces = {
    fe = {
      gateways = {
        "10.55.1.0/24" = "10.55.1.1";
        "2001:db8:1::/64" = "2001:db8:1::1";
      };
      mac = "52:54:00:12:01:01";
      networks = {
        "10.55.1.0/24" = [ "10.55.1.2" "10.55.1.3" ];
        "2001:db8:1::/64" = [ "2001:db8:1::2" ];
      };
    };
    srv = {
      gateways = {
        "10.55.2.0/24" = "10.55.2.1";
        "2001:db8:2::/64" = "2001:db8:2::1";
      };
      mac = "52:54:00:12:02:01";
      networks = {
        "10.55.2.0/24" = [ "10.55.2.4" ];
        "2001:db8:2::/64" = [ "2001:db8:2::5" "2001:db8:2::6" ];
      };
    };
  };

  testCases = {

    loopback = {
      name = "loopback";
      machine.imports = [ ../nixos ];
      testScript = ''
        $machine->waitForUnit("network.target");
        $machine->succeed("ip addr show lo | grep -q 'inet 127.0.0.1/8 '");
        $machine->succeed("ip addr show lo | grep -q 'inet6 ::1/128 '");
      '';
    };

    ping-vlans = {
      name = "ping-vlans";
      nodes.router = router;
      nodes.client =
        { pkgs, ... }:
        {
          imports = [ ../nixos ];
          virtualisation.vlans = [ 1 2 ];
          flyingcircus.enc.parameters.interfaces = encInterfaces;
        };
        testScript = ''
          startAll;
          $client->waitForUnit("network.target");
          $router->waitForUnit("network-online.target");

          print("\n* Router network overview\n");
          print($router->succeed("ip a"));
          print("\n* Client network overview\n");
          print($client->succeed("ip a"));

          subtest "ping fe", sub {
            $client->succeed("ping -I ethfe -c1 10.55.1.1");
            $client->succeed("ping -I ethfe -c1 2001:db8:1::1");
            $router->succeed("ping -c1 10.55.1.2");
            $router->succeed("ping -c1 10.55.1.3");
            $router->succeed("ping -c1 2001:db8:1::2");
          };

          subtest "ping srv", sub {
            $client->succeed("ping -I ethsrv -c1 10.55.2.1");
            $client->succeed("ping -I ethsrv -c1 2001:db8:2::1");
            $router->succeed("ping -c1 10.55.2.4");
            $router->succeed("ping -c1 2001:db8:2::5");
            $router->succeed("ping -c1 2001:db8:2::6");
          };

          subtest "ping default gateway", sub {
            $client->succeed("ping -c1 10.55.3.1");
            $client->succeed("ping -c1 2001:db8:3::1");
          };
        '';
      };

    # firewall = {
    #   name = "firewall";
    #   nodes.router = router;
    #   nodes.server =
    #     { pkgs, ... }:
    #     {
    #       imports = [ ../nixos ];
    #       virtualisation.vlans = [ 1 2 ];
    #       flyingcircus.enc.parameters.interfaces = encInterfaces;
    #       services.nginx.enable = true;
    #       services.nginx.virtualHosts.server = {
    #         root = "/tmp";
    #       };
    #     };
    #   # XXX problem: failing disable-ipv6-autoconf units
    #   # nginx unit won't start as result
    #   testScript = ''
    #     startAll;
    #     $server->succeed("echo hello world > /tmp/test");
    #     $server->waitForUnit("nginx.service");
    #     $router->waitForUnit("network-online.target");
    #     subtest "without firewall", sub {
    #       $router->fail("curl http://10.55.1.2/test");
    #       $router->fail("curl http://[2001:db8:1::2]/test");
    #       $router->fail("curl http://10.55.2.4/test");
    #       $router->fail("curl http://[2001:db8:2::5]/test");
    #     };
    #   '';
    # };

  };

in
mapAttrs (const (attrs: makeTest (attrs // {
  name = "network-${attrs.name}";
}))) testCases
