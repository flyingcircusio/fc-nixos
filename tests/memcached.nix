import ./make-test-python.nix ({ ... }:
let 
  ipv4 = "192.168.101.1";
  ipv6 = "2001:db8:f030:1c3::1";
in {
  name = "memcached";
  machine = 
    { ... }:
    {
      imports = [ ../nixos ../nixos/roles ];
      flyingcircus.roles.memcached.enable = true;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ ipv4 ];
            "2001:db8:f030:1c3::/64" = [ ipv6 ];
          };
          gateways = {};
        };
      };
    };

  testScript = ''
    machine.wait_for_unit('memcached.service')
    machine.wait_for_open_port(11211)
    # connecting with ipv6 often fails if we don't wait
    machine.wait_until_succeeds("ping -c1 ${ipv6}")

    machine.succeed("echo -e 'add my_key 0 60 11\\r\\nhello world\\r\\nquit' | nc ::1 11211 | grep STORED")
    machine.succeed("echo -e 'get my_key\\r\\nquit' | nc ${ipv4} 11211 | grep 'hello world'")
    machine.succeed("echo -e 'get my_key\\r\\nquit' | nc ${ipv6} 11211 | grep 'hello world'")

    # service user should be able to write to local config dir
    machine.succeed('sudo -u memcached touch /etc/local/memcached/memcached.json')
  '';
})