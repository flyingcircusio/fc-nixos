import ./make-test.nix ({ pkgs, ... }:
{
  name = "webproxy";
  nodes = {
    webproxy =
      { lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        environment.etc."local/varnish/newconfig.vcl".text = ''
          vcl 4.0;
          backend test {
            .host = "127.0.0.1";
            .port = "8081";
          }
        '';
        flyingcircus.roles.webproxy.enable = true;
      };
  };
  testScript = ''
    $webproxy->waitForUnit("varnish.service");
    $webproxy->waitForUnit("varnishncsa.service");

    $webproxy->execute(<<__SETUP__);
    echo 'Hello World!' > hello.txt
    ${pkgs.python3.interpreter} -m http.server 8080 &
    __SETUP__

    my $url = 'http://localhost:8008/hello.txt';
    my $curl = "curl -s $url";

    $webproxy->waitUntilSucceeds($curl);

    subtest "request should return expected output", sub {
      $webproxy->waitUntilSucceeds("$curl | grep -q 'Hello World!'");
    };

    subtest "varnishncsa should log requests", sub {
      $webproxy->waitUntilSucceeds("$curl && grep -q 'GET $url HTTP/' /var/log/varnish.log");
    };

    subtest "changing config and reloading should activate new config", sub {
      $webproxy->execute('ln -sf /etc/local/varnish/newconfig.vcl /etc/current-config/varnish.vcl');
      $webproxy->succeed('systemctl reload varnish');
      $webproxy->succeed('varnishadm vcl.list | grep active | grep -q newconfig');
    };
  '';
})
