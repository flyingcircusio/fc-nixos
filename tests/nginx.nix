import ./make-test-python.nix (
  {
    lib,
    pkgs,
    testlib,
    ...
  }:

  with lib;
  with testlib;

  let
    server6Srv = fcIP.srv6 1;
    server6Fe = fcIP.fe6 1;
    server4Srv = fcIP.srv4 1;
    server4Fe = fcIP.fe4 1;
    hosts = {
      "127.0.0.1" = [ "localhost" ];
      "::1" = [ "localhost" ];
      ${server6Fe} = [
        "server"
        "other"
      ];
      ${server4Fe} = [
        "server"
        "other"
      ];
    };

    expectedNginxMajorVersion = "1.30";

    rootInitial = pkgs.writeTextFile {
      name = "nginx-root-initial";
      text = "initial content\n";
      destination = "/index.html";
    };

    rootChanged = pkgs.writeTextFile {
      name = "nginx-root-changed";
      text = "changed content\n";
      destination = "/index.html";
    };

    owaspCoreRules = pkgs.fetchgit {
      url = "https://github.com/coreruleset/coreruleset.git";
      rev = "v3.3.0";
      sha256 = "0n8q5pa913cjbxhgmdi8jaivqnrc8y4pyqcv0y3si1i5dzn15lgw";
    };

    mkFCServer =
      {
        id,
        conf,
        rateLimit ? false,
      }:
      { pkgs, lib, ... }:
      {
        imports = [
          (testlib.fcConfig { inherit id; })
        ];

        networking.hosts = mkForce {
          "127.0.0.1" = [ "localhost" ];
          "::1" = [ "localhost" ];
          ${fcIP.srv6 id} = [
            "srv.local"
            "both.local"
          ];
          ${fcIP.srv4 id} = [
            "srv.local"
            "both.local"
          ];
          ${fcIP.fe6 id} = [
            "fe.local"
            "both.local"
          ];
          ${fcIP.fe4 id} = [
            "fe.local"
            "both.local"
          ];
        };

        flyingcircus.services.nginx.enable = true;
        services.nginx.virtualHosts = conf;
        flyingcircus.services.nginx.logPerVirtualHost = false;

        flyingcircus.services.nginx.rateLimit = lib.mkIf rateLimit {
          enable = true;
          maxRequestsPerSecond = 10;
          maxConcurrent = 100;
          burst = 50;
        };
      };

  in
  {
    name = "nginx";
    nodes = {
      server1 =
        { lib, pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig { id = 1; })
          ];

          networking.hosts = lib.mkForce hosts;

          environment.etc."proxy.http".text = ''
            HTTP/1.1 200 OK
            Content-Type: text/html; charset=UTF-8
            Server: netcat!

            <!doctype html>
            <html><body><h1>A webpage served by netcat</h1></body></html>
          '';

          environment.etc = {
            "local/nginx/modsecurity/modsecurity.conf".source = ../nixos/services/nginx/modsecurity.conf;

            "local/nginx/modsecurity/modsecurity_includes.conf".text = ''
              include modsecurity.conf
              include ${owaspCoreRules}/crs-setup.conf.example
              include ${owaspCoreRules}/rules/*.conf
              SecRule ARGS:testparam "@contains test" "id:1234,deny,status:999"
            '';
          };

          flyingcircus.logrotate.enable = true;
          flyingcircus.services.nginx.enable = true;
          flyingcircus.services.nginx.logPerVirtualHost = false;

          # Vhost for localhost is predefined by the nginx module and serves the
          # nginx status page which is expected by the sensu check.

          # Vhost for config reload check.
          # Explicitly use flyingcircus option here for regression testing
          flyingcircus.services.nginx.virtualHosts.server = {
            root = rootInitial;
            serverAliases = [ "other" ];
            addSSL = true;
            enableACME = true;
            locations."/proxy".proxyPass = "http://127.0.0.1:8008";

            extraConfig = ''
              modsecurity on;
              modsecurity_rules_file /etc/local/nginx/modsecurity/modsecurity_includes.conf;
            '';
          };

          # Display the nginx version on the 404 page.
          services.nginx.serverTokens = true;

          security.acme.certs.server.keyType = "rsa4096";

          # To test that sensu rules successfully eval
          flyingcircus.services.sensu-client = {
            enable = true;
            server = "1.2.3.4";
            password = "foo";
          };

          specialisation.brokenconfig.configuration = {
            flyingcircus.services.nginx.virtualHosts.server.locations."/proxy".extraConfig = ''
              not_existing_option true;
            '';
          };
        };

      server2 = mkFCServer {
        id = 2;
        conf = {
          "both.local" = {
            serverAliases = [
              "fe.local"
              "srv.local"
            ];
            addSSL = true;
            enableACME = true;
            locations."/".return = "200 'TESTOK'";
            extraConfig = ''
              access_log /var/log/nginx/perf.log performance;
            '';
          };
        };
      };

      server3 = mkFCServer {
        id = 3;
        conf = {
          "both.local" = {
            serverAliases = [
              "fe.local"
              "srv.local"
            ];
            addSSL = true;
            enableACME = true;
            listenAddresses = [ (fcIP.quote.fe4 3) ];

            locations."/".return = "200 'TESTOK'";
          };
        };
      };

      server4 = mkFCServer {
        id = 4;
        conf = {
          "both.local" = {
            serverAliases = [
              "fe.local"
              "srv.local"
            ];
            addSSL = true;
            enableACME = true;
            listenAddresses = [ (fcIP.quote.fe6 4) ];

            locations."/".return = "200 'TESTOK'";
          };
        };
      };

      server5 =
        { lib, pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig { id = 5; })
          ];

          flyingcircus.services.nginx = {
            enable = true;
            logPerVirtualHost = true;
            virtualHosts.server = {
              listenAddresses = [ "127.0.0.1" ];
              locations."/".return = "204";
            };
          };
        };

      server6 = mkFCServer {
        id = 6;
        rateLimit = true;
        conf = {
          "both.local" = {
            serverAliases = [
              "fe.local"
              "srv.local"
            ];
            addSSL = true;
            enableACME = true;
            listenAddresses = [ (fcIP.quote.fe6 6) ];

            locations."/".return = "200 'TESTOK'";
          };
        };
      };

      server7 =
        { lib, pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig { id = 7; })
          ];

          flyingcircus.roles.loki = {
            enable = true;
            storageSchedule.default = lib.mkForce [
              {
                startDate = "2024-09-10";
                backend = "filesystem";
              }
            ];
          };
          flyingcircus.roles.webgateway.enable = true;
          flyingcircus.services.nginx = {
            virtualHosts.server = {
              serverName = "_";
              listenAddresses = [ "127.0.0.1" ];
              locations."/".return = "204";
            };
          };

          networking.domain = "gocept.net";
          flyingcircus.encServices = [
            {
              address = "127.0.0.1";
              service = "loki-collector";
              ips = [
                (testlib.fcIP.srv4 7)
                (testlib.fcIP.srv6 7)
              ];
            }
          ];
        };

      # Eval only server. Should test that a vhost with useACMEHost successfully evals.
      server8 =
        { lib, pkgs, ... }:
        {
          imports = [
            (testlib.fcConfig { id = 8; })
          ];

          flyingcircus.services.sensu-client = {
            enable = true;
            server = "1.2.3.4";
            password = "foo";
          };

          flyingcircus.roles.webgateway.enable = true;
          flyingcircus.services.nginx = {
            virtualHosts.server = {
              useACMEHost = "server";
              forceSSL = true;
              enableACME = false;
            };
          };
          security.acme.certs.server = {
            dnsProvider = "pdns";
            environmentFile = pkgs.writeText "pdns-cred" "";
            group = "nginx";
          };
        };
    };

    testScript =
      { nodes, ... }:
      let
        sensuCheck = testlib.sensuCheckCmd nodes.server1;
      in
      ''
        def switch_specialisation(name, expected_fail: bool):
            path = "${nodes.server1.system.build.toplevel}/bin/switch-to-configuration" \
              if name is None \
              else f"${nodes.server1.system.build.toplevel}/specialisation/{name}/bin/switch-to-configuration"
            if expected_fail:
              server1.fail(f"{path} test")
            else:
              server1.succeed(f"{path} test")

        def prep(server):
          server.wait_for_unit('nginx.service')
          server.wait_for_open_port(81)

        def assert_file_permissions(expected, path):
          permissions = server1.succeed(f"stat {path} -c %a:%U:%G").strip()
          assert permissions == expected, f"expected: {expected}, got {permissions}"

        def assert_logdir():
          assert_file_permissions("755:nginx:nginx", "/var/log/nginx")
          assert_file_permissions("644:nginx:nginx", "/var/log/nginx/performance.log")
          assert_file_permissions("644:nginx:nginx", "/var/log/nginx/error.log")
          assert_file_permissions("644:nginx:nginx", "/var/log/nginx/access.log")

        def assert_reachable(server, intf, options = ""):
          server.succeed(f"curl -k https://{intf}.local --interface eth{intf} {options} | grep TESTOK")

        def assert_unreachable(server, intf, options = ""):
          server.fail(f"curl -k https://{intf}.local --interface eth{intf} {options} | grep TESTOK")

        # Prep all servers to avoid hard to read output.
        prep(server1)
        prep(server2)
        prep(server3)
        prep(server4)
        prep(server5)
        prep(server6)
        prep(server7)

        with subtest("proxy cache directory should be accessible only for nginx"):
          assert_file_permissions("700:nginx:nginx", "/var/cache/nginx/proxy")

        with subtest("log directory should have correct permissions"):
          assert_logdir()

        with subtest("dependencies between acme services and nginx-config-reload should be present"):
          # pre-renew reloading
          after = server1.succeed("systemctl show --property After --value nginx-config-reload.service")
          assert "acme-server.service" in after, f"acme-server.service missing: {after}"
          server1.succeed("stat /etc/systemd/system/acme-server.service.wants/nginx-config-reload.service")
          before = server1.succeed("systemctl show --property Before --value nginx-config-reload.service")
          assert "acme-order-renew-server.service" in before, f"acme-order-renew-server.service missing: {before}"
          # post-renew is almost impossible to test now, upstream Nixpkgs includes a test-case that
          # nginx doesn't get restarted when a new certificate is added

        with subtest("acme script should have lego calls with custom key-type and required default settings"):
          lego_calls = server1.succeed("grep lego $(systemctl cat acme-order-renew-server | awk -F '=' '/ExecStart=/ {print $2}')")
          print("lego calls emitted:")
          print("*" * 20)
          print(lego_calls)

          # Make sure we don't accidentally override defaults by specifying the custom key type
          assert "--key-type rsa4096" in lego_calls, "Can't find expected key-type option"
          assert "--http.webroot /var/lib/acme/acme-challenge" in lego_calls, "Can't find expected http.webroot option"
          assert "--email admin@flyingcircus.io" in lego_calls, "Can't find expected email option"

        # This "web server" is used for the next 2 subtests, keeps running forever.
        # proxy.log should be reset at the end of each subtest.
        server1.execute("(while true; do cat /etc/proxy.http | nc -l 8008 -N >> /tmp/proxy.log; done) >&2 &")

        with subtest("nginx should forward proxied host and server headers (primary name)"):
          server1.wait_until_succeeds("curl -sSf http://server/proxy/ && sleep 1 && grep X-Forwarded /tmp/proxy.log")
          _, proxy_log = server1.execute("cat /tmp/proxy.log")
          print(proxy_log)
          assert 'X-Forwarded-Host: server' in proxy_log, f"expected X-Forwarded-Host not found, got '{proxy_log}'"
          assert 'X-Forwarded-Server: server1' in proxy_log, f"expected X-Forwarded-Server not found, got '{proxy_log}'"
          # Reset proxy log
          server1.execute("truncate -s 0 /tmp/proxy.log")

        with subtest("nginx should forward proxied host and server headers (alias)"):
          server1.wait_until_succeeds("curl -sSf http://other/proxy/ && sleep 1 && grep X-Forwarded /tmp/proxy.log")
          _, proxy_log = server1.execute("cat /tmp/proxy.log")
          print(proxy_log)
          assert 'X-Forwarded-Host: other' in proxy_log, f"expected X-Forwarded-Host not found, got: '{proxy_log}'"
          assert 'X-Forwarded-Server: server1' in proxy_log, f"expected X-Forwarded-Server not found, got: '{proxy_log}'"
          # Reset proxy log
          server1.execute("truncate -s 0 /tmp/proxy.log")

        with subtest("nginx should log only anonymized IPs"):
          server1.succeed("curl -4 server -s -o/dev/null")
          server1.succeed("cat /var/log/nginx/access.log | grep '^${fcIPMap.fe4.prefix}0 - -'")
          server1.succeed("curl -6 server -s -o/dev/null")
          server1.succeed("cat /var/log/nginx/access.log | grep '^${fcIPMap.fe6.prefix} - -'")

        with subtest("nginx should have separate log files per vhost"):
          server5.succeed("curl -4 127.0.0.1 -s -o/dev/null")
          server5.succeed("cat /var/log/nginx/access-server.log | grep '^127.0.0.[0-9]\\+ - -'")

        with subtest("nginx should respond with configured content"):
          server1.succeed("curl server | grep -q 'initial content'")

        with subtest("running nginx should have the expected version"):
          server1.succeed("curl server/404 | grep -q ${expectedNginxMajorVersion}")

        with subtest("nginx should use changed config after reload"):
          # Replace config symlink with a new config file.
          server1.execute("sed 's#${rootInitial}#${rootChanged}#' /etc/nginx/nginx.conf > /etc/nginx/changed_nginx.conf")
          server1.execute("mv /etc/nginx/changed_nginx.conf /etc/nginx/nginx.conf")
          server1.systemctl("reload nginx")
          server1.wait_until_succeeds("curl server | grep -q 'changed content'")

        with subtest("logs should have correct permissions after reload"):
          assert_logdir()

        with subtest("logs should have correct permissions after logrotate"):
          server1.succeed("fc-logrotate -f")
          assert_logdir()

        with subtest("reload should recreate missing files"):
          server1.execute("rm /var/log/nginx/error.log")
          server1.succeed("systemctl reload nginx")
          assert_logdir()

        with subtest("restart should recreate missing files"):
          server1.execute("rm /var/log/nginx/error.log")
          server1.succeed("systemctl restart nginx")
          assert_logdir()


        with subtest("nginx modsecurity rules apply"):
          out = server1.wait_until_succeeds("curl -v http://server/?testparam=test")
          print(out)

        with subtest("service user should be able to write to local config dir"):
          server1.succeed('sudo -u nginx touch /etc/local/nginx/vhosts.json')

        with subtest("all sensu checks should be green"):
          server1.succeed("${sensuCheck "nginx_config"}")
          server1.succeed("${sensuCheck "nginx_worker_age"}")
          server1.succeed("${sensuCheck "nginx_status"}")

        with subtest("sensu checks should not mess with cache directory"):
          # When running with a wrong user, nginx might change permissions of the directories in /var/cache/nginx.
          # If running with a wrong config, it might create files in /tmp instead
          files = server1.succeed("ls /var/cache/nginx").rstrip().split("\n")
          for file in files:
            assert_file_permissions("700:nginx:nginx", f"/var/cache/nginx/{file}")

          # one of the files that would be created, see http-proxy-temp-path in nginx package
          server1.fail("test -e /tmp/nginx_proxy")

        with subtest("nginx_config check should be red when config is invalid"):
          switch_specialisation("brokenconfig", True)
          server1.fail("${sensuCheck "nginx_config"}")
          switch_specialisation(None, False)

        with subtest("killing the nginx process should trigger an automatic restart"):
          server1.succeed("pkill -9 -F /run/nginx/nginx.pid");
          server1.wait_until_succeeds("${sensuCheck "nginx_status"}")

        with subtest("status check should be red after shutting down nginx"):
          server1.systemctl('stop nginx')
          server1.fail("${sensuCheck "nginx_status"}")

        with subtest("[2] fc nginx should listen on fc by default"):
          prep(server2)
          assert_reachable(server2, "fe")
          assert_unreachable(server2, "srv")

        with subtest("[3] fc nginx with fe4 specified as listen should only listen on fe4"):
          prep(server3)
          assert_reachable(server3, "fe")
          assert_reachable(server3, "fe", "-4")
          assert_unreachable(server3, "fe", "-6")
          assert_unreachable(server3, "srv")

        with subtest("[4] fc nginx with fe6 specified as listen should only listen on fe6"):
          out = server4.succeed("journalctl -xeu nginx")
          print(out)
          prep(server4)
          assert_reachable(server4, "fe")
          assert_reachable(server4, "fe", "-6")
          assert_unreachable(server4, "fe" "-4")
          assert_unreachable(server4, "srv")

        with subtest("[5] not rate limiting connections"):
          import re
          # Running this against the other virtual hosts fails. I *think* this is
          # because we have a "return 200" statement on the root location there
          # which seems to short-circuit the rate limiting ... o_O
          out = server4.execute("${pkgs.apacheHttpd}/bin/ab -n 1000 -c 75 http://localhost:81/")[1]
          print(out)
          assert re.search("Complete requests: +1000", out), "incomplete test"
          error_match = re.search("Connect: ([0-9]+), Receive: ([0-9]+), Length: ([0-9]+), Exceptions: ([0-9]+)", out)
          assert not error_match, "Unexpected connection errors"

        with subtest("[6] rate limiting connections"):
          import re
          # Running this against the other virtual hosts fails. I *think* this is
          # because we have a "return 200" statement on the root location there
          # which seems to short-circuit the rate limiting ... o_O
          out = server6.execute("${pkgs.apacheHttpd}/bin/ab -n 1000 -c 75 http://localhost:81/")[1]
          print(out)
          assert re.search("Complete requests: +1000", out), "incomplete test"
          error_match = re.search("Connect: ([0-9]+), Receive: ([0-9]+), Length: ([0-9]+), Exceptions: ([0-9]+)", out)
          assert error_match, "Missing connection errors"
          errors = error_match.groups()  # type: ignore
          assert int(errors[0]) == 0
          assert int(errors[1]) == 0
          assert int(errors[2]) > 900
          assert int(errors[3]) == 0

        with subtest("[7] syslog connection to loki"):
          server7.wait_for_unit('nginx.service')
          server7.wait_for_unit('alloy.service')
          server7.wait_for_unit('loki.service')

          # We are fishing for a message here that implies that Nginx could not pass the the JSON-formatted log lines to Alloy via the syslog procotol.
          # Both the default transport protocol and the default syslog format for listening to incoming syslog messages on Alloy's end do not match
          # the transport protocol and syslog format that Nginx employs.
          # Since a misconfiguration of either end causes Nginx to log errors, this test was added to verify the absence of syslog-related errors in Nginx's journal output
          # which implies that proper configuration was applied.
          # When trying to intentionally fail the test we found that a single curl (or potentially the first ones after a fresh startup) does not trigger the error message.
          # This is probably due to some sort of caching / attempt at batching similar log lines.
          # That's why instead of just once we call out to curl a few additional times and then wait for a second to give Nginx enough time to register and report the error.

          server7.execute("curl -v -X POST http://127.0.0.1:80/")
          server7.execute("curl -v -X POST http://127.0.0.1:80/")
          server7.execute("curl -v -X POST http://127.0.0.1:80/")
          server7.execute("curl -v -X POST http://127.0.0.1:80/")

          import time
          time.sleep(1)

          server7.fail('journalctl -b -u nginx --grep "failed .* while logging to syslog"')

        with subtest("[8] Check that no coredumps happened"):
          for machine in machines:
            machine.succeed("(coredumpctl --json=short 2>&1 || true) | grep 'No coredumps found'")
      '';
  }
)
