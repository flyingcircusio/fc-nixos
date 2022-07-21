with builtins;

import ./make-test-python.nix ({ pkgs, testlib, ... }:

{
  name = "haproxy";
  nodes = {
    machine =
      { lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:34:56";
            bridged = false;
            networks = {
              "192.168.101.0/24" = [ "192.168.101.1" ];
              "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::1" ];
            };
            gateways = {};
          };
        };

        flyingcircus.services.haproxy.enable = true;

        services.haproxy.config = lib.mkForce ''
          global
            daemon
            chroot /var/empty
            log 127.0.0.1 local2

          defaults
            mode http
            log global
            option httplog
            timeout connect 5s
            timeout client 5s
            timeout server 5s

          frontend http-in
            bind *:8888
            default_backend server

          backend server
            server python 127.0.0.1:7000
        '';
      };
  };
  testScript = { nodes, ... }: ''
    machine.wait_for_unit("haproxy.service")
    machine.wait_for_unit("syslog.service")

    machine.execute("""
      echo 'Hello World!' > hello.txt
      ${pkgs.python3.interpreter} -m http.server 7000 >&2 &
    """)

    with subtest("request through haproxy should succeed"):
      machine.succeed("curl -s http://localhost:8888/hello.txt | grep -q 'Hello World!'")

    with subtest("log file entry should be present for request"):
      machine.sleep(1)
      machine.succeed('grep "haproxy.* http-in server/python .* /hello.txt" /var/log/haproxy.log')

    with subtest("service user should be able to write to local config dir"):
      machine.succeed('sudo -u haproxy touch /etc/local/haproxy/haproxy.cfg')

    with subtest("reload should work"):
      machine.succeed("systemctl reload haproxy")
      machine.wait_until_succeeds('journalctl -g "Reloaded HAProxy" --no-pager')

    with subtest("reload should trigger a restart if /run/haproxy is missing"):
      machine.execute("rm -rf /run/haproxy")
      machine.succeed("systemctl reload haproxy")
      machine.wait_until_succeeds("stat /run/haproxy/haproxy.sock 2> /dev/null")
      machine.wait_until_succeeds('journalctl -g "Socket not present which is needed for reloading, restarting instead" --no-pager')

    with subtest("sensu haproxy config check should be green"):
      machine.succeed("${testlib.sensuCheckCmd nodes.machine "haproxy_config"}")

    with subtest("haproxy check script should be green"):
      machine.succeed("${pkgs.fc.check-haproxy}/bin/check_haproxy /var/log/haproxy.log")
  '';

})
