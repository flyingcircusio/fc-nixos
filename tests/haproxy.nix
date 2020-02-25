import ./make-test.nix ({ pkgs, ... }:
{
  name = "haproxy";
  nodes = {
    machine =
      { lib, ... }:
      {
        imports = [ ../nixos ];
        flyingcircus.services.haproxy.enable = true;
        services.haproxy.config = lib.mkForce ''
          global
            daemon
            chroot /var/empty
            user haproxy
            group haproxy
            log localhost local2

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
  testScript = ''
    $machine->waitForUnit("haproxy.service");
    $machine->waitForUnit("syslog.service");

    $machine->execute(<<__SETUP__);
    echo 'Hello World!' > hello.txt
    ${pkgs.python3.interpreter} -m http.server 7000 &
    __SETUP__

    subtest "request through haproxy should succeed", sub {
      $machine->succeed("curl -s http://localhost:8888/hello.txt | grep -q 'Hello World!'");
    };

    subtest "log file entry should be present for request", sub {
      $machine->sleep(0.5);
      $machine->succeed('grep "haproxy.* http-in server/python .* /hello.txt" /var/log/haproxy.log');
    };

    subtest "service user should be able to write to local config dir", sub {
      $machine->succeed('sudo -u haproxy touch /etc/local/haproxy/haproxy.cfg');
    };

    subtest "haproxy check script should be green", sub {
      $machine->succeed("${pkgs.fc.check-haproxy}/bin/check_haproxy /var/log/haproxy.log");
    };
  '';
})
