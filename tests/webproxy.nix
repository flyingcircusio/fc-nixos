import ./make-test-python.nix ({ pkgs, ... }:
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

        flyingcircus.enc.parameters.interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ "192.168.101.1" ];
            "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::3" ];
          };
          gateways = {};
        };
          
      };
  };
  testScript = ''
    webproxy.wait_for_unit("varnish.service")
    webproxy.wait_for_unit("varnishncsa.service")

    webproxy.execute("""
        echo 'Hello World!' > hello.txt
        ${pkgs.python3.interpreter} -m http.server 8080 &
        """)

    url = 'http://localhost:8008/hello.txt'
    curl = "curl -s " + url

    webproxy.wait_until_succeeds(curl)

    with subtest("request should return expected output"):
        webproxy.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")

    with subtest("varnishncsa should log requests"):
        webproxy.wait_until_succeeds(f"{curl} && grep -q 'GET {url} HTTP/' /var/log/varnish.log")

    with subtest("changing config and reloading should activate new config"):
        webproxy.execute('ln -sf /etc/local/varnish/newconfig.vcl /etc/current-config/varnish.vcl')
        webproxy.succeed('systemctl reload varnish')
        webproxy.succeed('varnishadm vcl.list | grep active | grep -q newconfig')
  '';
})
