import ./make-test-python.nix (
  { pkgs, testlib, ... }:
  let
    vinylport = 8008;
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
    name = "webproxy";
    interactive.sshBackdoor.enable = true;
    nodes = {
      webproxy_mixed_config =
        { lib, ... }:
        let
          serverport = 8080;
        in
        {
          imports = [ (testlib.fcConfig { id = 3; }) ];

          flyingcircus.roles.webproxy.enable = true;

          environment.etc."local/vinyl-cache/default.vcl".text = ''
            vcl 4.0;

            backend test {
              .host = "127.0.0.1";
              .port = "${builtins.toString serverport}";
            }
          '';

          flyingcircus.services.vinyl-cache.virtualHosts.foo = {
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

      webproxy_config_varnish_namespace_module =
        { lib, ... }:
        let
          serverport = 8080;
        in
        {
          imports = [ (testlib.fcConfig { id = 4; }) ];

          flyingcircus.roles.webproxy.enable = true;

          flyingcircus.services.varnish.virtualHosts.foo = {
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

      webproxy_config_varnish_namespace_file =
        { lib, ... }:
        let
          serverport = 8080;
        in
        {
          imports = [ (testlib.fcConfig { id = 5; }) ];

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

      webproxy_old_vinyl =
        { lib, ... }:
        let
          serverport = 8080;
        in
        {
          imports = [ (testlib.fcConfig { id = 2; }) ];

          flyingcircus.roles.webproxy.enable = true;

          environment.etc."local/vinyl-cache/default.vcl".text = ''
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
            vinyl-switch-test.configuration =
              let
                switchport = serverport + 1;
              in
              {
                system.nixos.tags = [ "vinyl-switch-test" ];
                flyingcircus.services.vinyl-cache.virtualHosts.test = lib.mkForce {
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

            vinyl-broken-config-test.configuration = {
              system.nixos.tags = [ "vinyl-broken-config-test" ];
              flyingcircus.services.vinyl-cache.virtualHosts.test = lib.mkForce {
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

          flyingcircus.services.vinyl-cache.virtualHosts.test = {
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

        webproxy.wait_for_unit("vinyl-cache.service")
        webproxy.wait_for_unit("vinylncsa.service")
        webproxy.wait_for_unit("helloserver.service")

        url = 'http://localhost:${builtins.toString vinylport}/hello.txt'
        curl = "curl -s " + url

        webproxy.wait_until_succeeds(curl)

        with subtest("request should return expected output"):
            webproxy.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")

        with subtest("vinylncsa should log requests"):
            webproxy.wait_until_succeeds(f"{curl} && grep -q 'GET {url} HTTP/' /var/log/vinyl-cache/vinyl-cache.log")

        with subtest("sensu checks should be successful"):
            webproxy.succeed("${nodes.webproxy.flyingcircus.services.sensu-client.checks.vinyl_cache_http.command}")
            webproxy.succeed("${nodes.webproxy.flyingcircus.services.sensu-client.checks.vinyl_cache_status.command}")

        with subtest("vinyl pid should be the same across small configuration changes"):
          old_pid = webproxy.succeed("systemctl show vinyl-cache.service --property MainPID --value")
          old_port = webproxy.succeed("vinyladm vcl.show label-test | grep \"\\.port\" | cut -d \"\\\"\" -f 2")
          webproxy.succeed("/run/current-system/specialisation/vinyl-switch-test/bin/switch-to-configuration switch")
          new_pid = webproxy.succeed("systemctl show vinyl-cache.service --property MainPID --value")
          new_port = webproxy.succeed("vinyladm vcl.show label-test | grep \"\\.port\" | cut -d \"\\\"\" -f 2")

          assert old_pid == new_pid, f"pid is different: {old_pid} != {new_pid}"
          assert old_port != new_port, f"port is identical: {old_port} == {new_port}"

        with subtest("old vinyl config should work before and after reload"):
          webproxy_old_vinyl.wait_for_unit("vinyl-cache.service")
          webproxy_old_vinyl.wait_for_unit("helloserver.service")
          webproxy_old_vinyl.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")
          webproxy_old_vinyl.systemctl("reload vinyl")
          webproxy_old_vinyl.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")

        with subtest("Vinyl should still support configuring via Varnish file"):
          webproxy_config_varnish_namespace_file.wait_for_unit("vinyl-cache.service")
          webproxy_config_varnish_namespace_file.wait_for_unit("helloserver.service")
          webproxy_config_varnish_namespace_file.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")
          webproxy_config_varnish_namespace_file.systemctl("reload vinyl")
          webproxy_config_varnish_namespace_file.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")


        with subtest("Vinyl should still support configuring via Varnish NixOS module"):
          webproxy_config_varnish_namespace_module.wait_for_unit("vinyl-cache.service")
          webproxy_config_varnish_namespace_module.wait_for_unit("helloserver.service")
          webproxy_config_varnish_namespace_module.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")
          webproxy_config_varnish_namespace_module.systemctl("reload vinyl")
          webproxy_config_varnish_namespace_module.wait_until_succeeds(f"{curl} | grep -q 'Hello World!'")

        with subtest("vinyl reloads with cold vcl and the cold vcl is discarded"):
          webproxy.succeed("vinyladm vcl.list | grep \"0 boot\"")
          webproxy.succeed("vinyladm vcl.state boot cold")
          webproxy.systemctl("reload vinyl-cache")
          webproxy.fail("vinyladm vcl.list | grep cold")

        with subtest("vinyl reloads with multiple cold vcls and the cold vcls are discarded"):
          webproxy.systemctl("restart vinyl-cache")
          webproxy.succeed("vinyladm vcl.list | grep \"0 boot\"")
          webproxy.succeed("vinyladm vcl.state boot cold")
          webproxy.succeed("vinyladm vcl.load another_cold_vcl ${cold_testvcl} cold")
          webproxy.systemctl("reload vinyl-cache")
          webproxy.fail("vinyladm vcl.list | grep \" cold \"")

        with subtest("vinyl with broken config should fail to switch"):
          # switching to a different specialisation requires a reboot, otherwise `/run/current-system/specialisation/` is empty
          # reboot is broken since it doesn't set `booted = False` and the VM will not boot with `booted = True`
          webproxy.shutdown()
          webproxy.start()
          webproxy.wait_for_unit("vinyl-cache.service")
          webproxy.fail("/run/current-system/specialisation/vinyl-broken-config-test/bin/switch-to-configuration switch")

        with subtest("fallback configuration for vinyl works if the other conditions don't match"):
          # verify that requests with the "Test" host header are being handled by the explicitly defined vinyl backend
          # while others are handled by the fallback backend
          # the fallback configuration points at a working http server that serves a hello.txt while the other
          # (explicitly configured) backend which is selected when adding the "Test" host header doesn't serve anything
          webproxy_mixed_config.wait_for_unit("vinyl-cache.service")
          webproxy_mixed_config.succeed("vinyladm vcl.list | grep \"localhost\"")
          webproxy_mixed_config.succeed("vinyladm vcl.show")
          webproxy_mixed_config.fail(f"curl --fail -H 'Host: Test' 127.0.0.1:8008/hello.txt")
          webproxy_mixed_config.succeed(f"curl --fail 127.0.0.1:8008/hello.txt")
      '';
  }
)
