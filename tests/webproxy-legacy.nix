import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    varnishport = 8008;
    serverport = 8080;

    cold_testvcl = pkgs.writeText "test_vcl" ''
      vcl 4.0;
      backend test_another_cold_vcl {
        .host = "127.0.0.1";
        .port = "200";
      }
    '';
  in
  {
    name = "webproxy-legacy";
    nodes = {
      webproxy_mixed_config =
        { lib, ... }:
        let
          serverport = 8080;
        in
        {
          imports = [ (testlib.fcConfig { id = 3; }) ];

          flyingcircus.roles.webproxy.enable = true;
          flyingcircus.roles.webproxy.package = pkgs.varnish80;

          environment.etc."local/varnish/default.vcl".text = ''
            vcl 4.0;

            backend test {
              .host = "127.0.0.1";
              .port = "${builtins.toString serverport}";
            }
          '';

          flyingcircus.services.varnish.virtualHosts.foo = {
            condition = "req.http.Host == \"Test\"";
            config = ''
              vcl 4.0;

              backend test {
                .host = "127.0.0.1";
                .port = "666";
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

      webproxy_old_varnish =
        { lib, ... }:
        let
          serverport = 8080;
        in
        {
          imports = [ (testlib.fcConfig { id = 2; }) ];

          flyingcircus.roles.webproxy.enable = true;
          flyingcircus.roles.webproxy.package = pkgs.varnish80;

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
          imports = [ (testlib.fcConfig { id = 1; }) ];

          specialisation = {
            varnish-switch-test.configuration =
              let
                switchport = serverport + 1;
              in
              {
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

            varnish-broken-config-test.configuration = {
              system.nixos.tags = [ "varnish-broken-config-test" ];
              flyingcircus.services.varnish.virtualHosts.test = lib.mkForce {
                condition = "true";
                config = ''
                  vcl 4.0;
                  backend test {
                    .host = "127.0.0.1";
                    .port = "80;
                  }
                '';
              };

            };
          };

          flyingcircus.roles.webproxy.enable = true;
          flyingcircus.roles.webproxy.package = pkgs.varnish80;

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

    testScript =
      { nodes, ... }:
      ''
        start_all()

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

        with subtest("sensu checks should be successful"):
            webproxy.succeed("${nodes.webproxy.flyingcircus.services.sensu-client.checks.varnish_http.command}")
            webproxy.succeed("${nodes.webproxy.flyingcircus.services.sensu-client.checks.varnish_status.command}")

        with subtest("varnish pid should be the same across small configuration changes"):
          old_pid = webproxy.succeed("systemctl show varnish.service --property MainPID --value")
          old_port = webproxy.succeed("varnishadm vcl.show label-test | grep \"\\.port\" | cut -d \"\\\"\" -f 2")
          webproxy.succeed("/run/current-system/specialisation/varnish-switch-test/bin/switch-to-configuration switch")
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

        with subtest("varnish reloads with cold vcl and the cold vcl is discarded"):
          webproxy.succeed("varnishadm vcl.list | grep \"0 boot\"")
          webproxy.succeed("varnishadm vcl.state boot cold")
          webproxy.systemctl("reload varnish")
          webproxy.fail("varnishadm vcl.list | grep cold")

        with subtest("varnish reloads with multiple cold vcls and the cold vcls are discarded"):
          webproxy.systemctl("restart varnish")
          webproxy.succeed("varnishadm vcl.list | grep \"0 boot\"")
          webproxy.succeed("varnishadm vcl.state boot cold")
          webproxy.succeed("varnishadm vcl.load another_cold_vcl ${cold_testvcl} cold")
          webproxy.systemctl("reload varnish")
          webproxy.fail("varnishadm vcl.list | grep \" cold \"")

        with subtest("varnish with broken config should fail to switch"):
          # switching to a different specialisation requires a reboot, otherwise `/run/current-system/specialisation/` is empty
          # reboot is broken since it doesn't set `booted = False` and the VM will not boot with `booted = True`
          webproxy.shutdown()
          webproxy.start()
          webproxy.wait_for_unit("varnish.service")
          webproxy.fail("/run/current-system/specialisation/varnish-broken-config-test/bin/switch-to-configuration switch")

        with subtest("fallback configuration for varnish works if the other conditions don't match"):
          # verify that requests with the "Test" host header are being handled by the explicitly defined varnish backend
          # while others are handled by the fallback backend
          # the fallback configuration points at a working http server that serves a hello.txt while the other
          # (explicitly configured) backend which is selected when adding the "Test" host header doesn't serve anything
          webproxy_mixed_config.wait_for_unit("varnish.service")
          webproxy_mixed_config.succeed("varnishadm vcl.list | grep \"localhost\"")
          webproxy_mixed_config.succeed("varnishadm vcl.show")
          webproxy_mixed_config.fail(f"curl --fail -H 'Host: Test' 127.0.0.1:8008/hello.txt")
          webproxy_mixed_config.succeed(f"curl --fail 127.0.0.1:8008/hello.txt")
      '';
  }
)
