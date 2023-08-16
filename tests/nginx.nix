import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:

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
    ${server6Fe} = [ "server" "other" ];
    ${server4Fe} = [ "server" "other" ];
  };

  expectedNginxMajorVersion = "1.24";

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

  mkFCServer = {
    id,
    conf
  }:
  { pkgs, ... }: {
    imports = [
      (testlib.fcConfig { inherit id; })
    ];

    networking.hosts = mkForce {
      "127.0.0.1" = [ "localhost" ];
      "::1" = [ "localhost" ];
      ${fcIP.srv6 id} = [ "srv.local" "both.local" ];
      ${fcIP.srv4 id} = [ "srv.local" "both.local" ];
      ${fcIP.fe6 id} = [ "fe.local" "both.local" ];
      ${fcIP.fe4 id} = [ "fe.local" "both.local" ];
    };

    flyingcircus.services.nginx.enable = true;
    flyingcircus.services.nginx.virtualHosts = conf;
  };

in {
  name = "nginx";
  nodes = {
    server1 = { lib, pkgs, ... }: {
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
        "local/nginx/modsecurity/modsecurity.conf".source =
          ../nixos/services/nginx/modsecurity.conf;

        "local/nginx/modsecurity/modsecurity_includes.conf".text =
          ''
          include modsecurity.conf
          include ${owaspCoreRules}/crs-setup.conf.example
          include ${owaspCoreRules}/rules/*.conf
          SecRule ARGS:testparam "@contains test" "id:1234,deny,status:999"
          '';
      };

      flyingcircus.logrotate.enable = true;
      flyingcircus.services.nginx.enable = true;

      # Vhost for localhost is predefined by the nginx module and serves the
      # nginx status page which is expected by the sensu check.

      # Vhost for config reload check.
      services.nginx.virtualHosts.server = {
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
    };

    server2 = mkFCServer {
      id = 2;
      conf = {
        "both.local" = {
          serverAliases = [ "fe.local" "srv.local" ];
          addSSL = true;
          locations."/".return = "200 'TESTOK'";
        };
      };
    };

    server3 = mkFCServer {
      id = 3;
      conf = {
        "both.local" = {
          serverAliases = [ "fe.local" "srv.local" ];
          addSSL = true;
          listenAddress = fcIP.quote.fe4 3;

          locations."/".return = "200 'TESTOK'";
        };
      };
    };

    server4 = mkFCServer {
      id = 4;
      conf = {
        "both.local" = {
          serverAliases = [ "fe.local" "srv.local" ];
          addSSL = true;
          listenAddress6 = fcIP.quote.fe6 4;

          locations."/".return = "200 'TESTOK'";
        };
      };
    };
  };

  testScript = { nodes, ... }:
  let
    sensuCheck = testlib.sensuCheckCmd nodes.server1;
  in ''
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

    def assert_reachable(server, intf):
      server.succeed("curl -k https://" + intf + " | grep TESTOK")

    def assert_unreachable(server, intf):
      server.fail("curl -k https://" + intf + " | grep TESTOK")

    # Prep all servers to avoid hard to read output.
    prep(server1)
    prep(server2)
    prep(server3)
    prep(server4)

    with subtest("proxy cache directory should be accessible only for nginx"):
      assert_file_permissions("700:nginx:nginx", "/var/cache/nginx/proxy")

    with subtest("log directory should have correct permissions"):
      assert_logdir()

    with subtest("dependencies between acme services and nginx-config-reload should be present"):
      after = server1.succeed("systemctl show --property After --value nginx-config-reload.service")
      assert "acme-server.service" in after, f"acme.server.service missing: {after}"
      before = server1.succeed("systemctl show --property Before --value nginx-config-reload.service")
      assert "acme-finished-server.target" in before, f"acme-finished-server.target missing: {before}"
      server1.succeed("stat /etc/systemd/system/acme-server.service.wants/nginx-config-reload.service")

    with subtest("acme script should have lego calls with custom key-type and required default settings"):
      lego_calls = server1.succeed("grep lego $(systemctl cat acme-server | awk -F '=' '/ExecStart=/ {print $2}')")
      assert "'--key-type' 'rsa4096'" in lego_calls, "Can't find expected key-type option"
      # Make sure we don't accidentally override defaults by specifying the custom key type
      assert "'--http.webroot' '/var/lib/acme/acme-challenge'" in lego_calls, "Can't find expected http.webroot option"
      assert "'--email' 'admin@flyingcircus.io'" in lego_calls, "Can't find expected email option"

    with subtest("nginx should forward proxied host and server headers (primary name)"):
      server1.execute("cat /etc/proxy.http | nc -l 8008 -N > /tmp/proxy.log &")
      server1.sleep(3)
      server1.succeed("curl http://server/proxy/")
      server1.sleep(2)
      _, proxy_log = server1.execute("cat /tmp/proxy.log")
      print(proxy_log)
      assert 'X-Forwarded-Host: server' in proxy_log, f"expected X-Forwarded-Host not found, got '{proxy_log}'"
      assert 'X-Forwarded-Server: server' in proxy_log, f"expected X-Forwarded-Server not found, got '{proxy_log}'"

    with subtest("nginx should forward proxied host and server headers (alias)"):
      server1.execute("cat /etc/proxy.http | nc -l 8008 -N > /tmp/proxy.log &")
      server1.sleep(3)
      server1.succeed("curl http://other/proxy/")
      server1.sleep(2)
      _, proxy_log = server1.execute("cat /tmp/proxy.log")
      print(proxy_log)
      assert 'X-Forwarded-Host: other' in proxy_log, f"expected X-Forwarded-Host not found, got: '{proxy_log}'"
      assert 'X-Forwarded-Server: server' in proxy_log, f"expected X-Forwarded-Server not found, got: '{proxy_log}'"

    with subtest("nginx should log only anonymized IPs"):
      server1.succeed("curl -4 server -s -o/dev/null")
      server1.succeed("cat /var/log/nginx/access.log | grep '^${fcIPMap.fe4.prefix}0 - -'")
      server1.succeed("curl -6 server -s -o/dev/null")
      server1.succeed("cat /var/log/nginx/access.log | grep '^${fcIPMap.fe6.prefix} - -'")

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

    with subtest("nginx should use changed binary after reload"):
      # Prepare change to mainline nginx. We are not interested in testing mainline itself here.
      # We only need it as a different version so we can test binary reloading.
      server1.execute("ln -sfT ${pkgs.nginxMainline} /etc/nginx/running-package")
      # Go to mainline (this doesn't overwrite /etc/nginx/running-package).
      server1.succeed("nginx-reload-master")
      server1.wait_until_succeeds("curl server/404 | grep -q ${pkgs.nginxMainline.version}")
      # Back to initial binary from nginx stable (this does overwrite /etc/nginx/running-package with the wanted package).
      server1.systemctl("reload nginx")
      server1.wait_until_succeeds("curl server/404 | grep -q ${expectedNginxMajorVersion}")

    with subtest("log directory should have correct permissions after binary reload"):
      assert_logdir()

    with subtest("logs should have correct permissions after logrotate"):
      server1.succeed("fc-logrotate -f")
      assert_logdir()

    with subtest("reload should fix wrong log permissions and recreate missing files"):
      server1.execute("chown nginx:nginx /var/log/nginx/performance.log")
      server1.execute("chown nobody:nobody /var/log/nginx/access.log")
      server1.execute("rm /var/log/nginx/error.log")
      server1.succeed("systemctl reload nginx")
      assert_logdir()

    with subtest("restart should fix wrong log permissions and recreate missing files"):
      server1.execute("chown nginx:nginx /var/log/nginx/performance.log")
      server1.execute("chown nobody:nobody /var/log/nginx/access.log")
      server1.execute("rm /var/log/nginx/error.log")
      server1.succeed("systemctl restart nginx")
      assert_logdir()

    with subtest("nginx modsecurity rules apply"):
      out = server1.succeed("curl -v http://server/?testparam=test")
      print(out)

    with subtest("service user should be able to write to local config dir"):
      server1.succeed('sudo -u nginx touch /etc/local/nginx/vhosts.json')

    with subtest("all sensu checks should be green"):
      server1.succeed("${sensuCheck "nginx_config"}")
      server1.succeed("${sensuCheck "nginx_worker_age"}")
      server1.succeed("${sensuCheck "nginx_status"}")

    with subtest("killing the nginx process should trigger an automatic restart"):
      server1.succeed("pkill -9 -F /run/nginx/nginx.pid");
      server1.wait_until_succeeds("${sensuCheck "nginx_status"}")

    with subtest("status check should be red after shutting down nginx"):
      server1.systemctl('stop nginx')
      server1.fail("${sensuCheck "nginx_status"}")

    with subtest("[2] fc nginx should listen on fc by default"):
      prep(server2)
      assert_reachable(server2, "fe.local")
      assert_unreachable(server2, "srv.local")

    with subtest("[3] fc nginx with fe4 specified as listen should only listen on fe4"):
      prep(server3)
      assert_reachable(server3, "fe.local")
      assert_reachable(server3, "fe.local -4")
      assert_unreachable(server3, "fe.local -6")
      assert_unreachable(server3, "srv.local")

    with subtest("[4] fc nginx with fe6 specified as listen should only listen on fe6"):
      out = server4.succeed("journalctl -xeu nginx")
      print(out)
      prep(server4)
      assert_reachable(server4, "fe.local")
      assert_reachable(server4, "fe.local -6")
      assert_unreachable(server4, "fe.local -4")
      assert_unreachable(server4, "srv.local")
  '';
})
