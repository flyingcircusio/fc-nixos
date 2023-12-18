import ./make-test-python.nix ({ pkgs, testlib, ... }: let
  varnishport = 8008;
  serverport = 8080;
in {
  name = "webproxy";
  nodes = {
    webproxy_old_varnish =
      {lib, ... }: let
        serverport = 8080;
      in {
        imports = [ (testlib.fcConfig { id = 1; }) ];

        flyingcircus.roles.webproxy.enable = true;

        environment.etc."local/varnish/default.vcl".text = ''
          vcl 4.0;

          backend test {
            .host = "127.0.0.1";
            .port = "${builtins.toString serverport}";
          }
        '';

        systemd.services.helloserver = {
          wantedBy = [ "multi-user.target" ];
          script = ''
            echo 'Hello World!' > hello.txt
            ${pkgs.python3.interpreter} -m http.server ${builtins.toString serverport} >&2
          '';
        };
      };

    webproxy =
      { lib, ... }:
      {
        imports = [ (testlib.fcConfig { id = 2; }) ];

        specialisation.varnish-switch-test.configuration = let
          switchport = serverport + 1;
        in {
          system.nixos.tags = [ "varnish-switch-test" ];
          flyingcircus.services.varnish.virtualHosts.test = lib.mkForce {
            condition = "true";
            config = ''
              vcl 4.0;
              backend test {
                .host = "127.0.0.1";
                .port = "${builtins.toString switchport}";
              }
            '';
          };

          systemd.services.helloserver = {
            wantedBy = [ "multi-user.target" ];
            script = ''
              echo 'Hello World!' > hello.txt
              ${pkgs.python3.interpreter} -m http.server ${builtins.toString switchport} >&2
            '';
          };
        };

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

    with subtest("varnish pid should be the same across small configuration changes"):
      old_pid = webproxy.succeed("systemctl show varnish.service --property MainPID --value")
      old_port = webproxy.succeed("varnishadm vcl.show label-test | grep \"\\.port\" | cut -d \"\\\"\" -f 2")
      webproxy.wait_until_succeeds("/run/current-system/specialisation/varnish-switch-test/bin/switch-to-configuration switch")
      new_pid = webproxy.succeed("systemctl show varnish.service --property MainPID --value")
      new_port = webproxy.succeed("varnishadm vcl.show label-test | grep \"\\.port\" | cut -d \"\\\"\" -f 2")

      assert old_pid == new_pid, f"pid is different: {old_pid} != {new_pid}"
      assert old_port != new_port, f"port is identical: {old_port} == {new_port}"

    with subtest("old varnish config should work before and after reload"):
      webproxy_old_varnish.wait_for_unit("varnish.service")
      webproxy_old_varnish.wait_for_unit("helloserver.service")
      webproxy_old_varnish.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")
      webproxy_old_varnish.systemctl("reload varnish")
      webproxy_old_varnish.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")
  '';
})
