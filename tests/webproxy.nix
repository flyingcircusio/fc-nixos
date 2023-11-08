import ./make-test-python.nix ({ pkgs, ... }: let
  varnishport = 8008;
  serverport = 8080;
in {
  name = "webproxy";
  nodes = {
    webproxy =
      { lib, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.roles.webproxy.enable = true;

        flyingcircus.services.varnish.virtualHosts.test = {
          condition = "true";
          config = ''
            vcl 4.0;
            backend test {
              .host = "127.0.0.1";
              .port = "${builtins.toString serverport}";
            }
          '';
        };

        flyingcircus.enc.parameters.interfaces.srv = {
          mac = "52:54:00:12:34:56";
          bridged = false;
          networks = {
            "192.168.101.0/24" = [ "192.168.101.1" ];
            "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::3" ];
          };
          gateways = {};
        };

        systemd.services.helloserver = {
          wantedBy = [ "multi-user.target" ];
          script = ''
            echo 'Hello World!' > hello.txt
            ${pkgs.python3.interpreter} -m http.server ${builtins.toString serverport} >&2
          '';
        };
      };
  };
  testScript = ''
    webproxy.wait_for_unit("varnish.service")
    webproxy.wait_for_unit("varnishncsa.service")
    webproxy.wait_for_unit("helloserver.service")

    url = 'http://localhost:${builtins.toString varnishport}/hello.txt'
    curl = "curl -s " + url

    webproxy.wait_until_succeeds(curl)

    with subtest("request should return expected output"):
        webproxy.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")

    with subtest("varnishncsa should log requests"):
        webproxy.wait_until_succeeds(f"{curl} && grep -q 'GET {url} HTTP/' /var/log/varnish.log")
  '';
})
