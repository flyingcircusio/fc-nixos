import ./make-test.nix ({ pkgs, ... }:
{
  name = "haproxy";
  nodes = {
    webproxy =
      { lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.roles.webproxy.enable = true;
      };
  };
  testScript = ''
    $webproxy->waitForUnit("varnish.service");

    $webproxy->execute(<<__SETUP__);
    echo 'Hello World!' > hello.txt
    ${pkgs.python3.interpreter} -m http.server 8080 &
    __SETUP__

    my $curl = 'curl -s http://localhost:8008/hello.txt';
    $webproxy->waitUntilSucceeds($curl);
    $webproxy->succeed($curl) =~ /Hello World!/ or
      die "expected output missing";

    # check log file entry
    sleep 1;
    $webproxy->succeed(<<_EOT_);
    grep "GET http://localhost:8008/hello.txt HTTP/" /var/log/varnish.log
    _EOT_
  '';
})
