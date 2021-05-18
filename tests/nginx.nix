import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:

let
  netLoc4Srv = "10.0.1";
  server4Srv = netLoc4Srv + ".2";

  netLoc6Srv = "2001:db8:1::";
  server6Srv = netLoc6Srv + "2";

  net4Fe = "10.0.3";
  client4Fe = net4Fe + ".1";
  server4Fe = net4Fe + ".2";

  net6Fe = "2001:db8:3::";
  client6Fe = net6Fe + "1";
  server6Fe = net6Fe + "2";

  hosts = {
    "127.0.0.1" = [ "localhost" ];
    "::1" = [ "localhost" ];
    ${server6Fe} = [ "server" "other" ];
    ${server4Fe} = [ "server" "other" ];
  };

  stableMajorVersion = "1.18";
  mainlineMajorVersion = "1.20";

  rootInitial = pkgs.runCommand "nginx-root-initial" {} ''
    mkdir $out
    echo initial content > $out/index.html
  '';

  rootChanged = pkgs.runCommand "nginx-root-changed" {} ''
    mkdir $out
    echo changed content > $out/index.html
  '';

  owaspCoreRules = pkgs.fetchgit {
    url = "https://github.com/coreruleset/coreruleset.git";
    rev = "v3.3.0";
    sha256 = "0n8q5pa913cjbxhgmdi8jaivqnrc8y4pyqcv0y3si1i5dzn15lgw";
  };
in {
  name = "nginx";
  nodes = {
    server = { lib, pkgs, ... }: {
      imports = [ ../nixos ];

      networking.hosts = lib.mkForce hosts;

      flyingcircus.enc.parameters = {
        resource_group = "test";
        interfaces.srv = {
          mac = "52:54:00:12:01:01";
          networks = {
            "${netLoc4Srv}.0/24" = [ server4Srv ];
            "${netLoc6Srv}/64" = [ server6Srv ];
          };
          gateways = {};
        };
        interfaces.fe = {
          mac = "52:54:00:12:02:01";
          networks = {
            "${net4Fe}.0/24" = [ server4Fe ];
            "${net6Fe}/64" = [ server6Fe ];
          };
          gateways = {};
        };
      };

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

      virtualisation.vlans = [ 1 2 ];
    };
  };

  testScript = { nodes, ... }:
  let
    sensuCheck = testlib.sensuCheckCmd nodes.server;
  in ''
    server.wait_for_unit('nginx.service')
    server.wait_for_open_port(80)

    def assert_file_permissions(expected, path):
      permissions = server.succeed(f"stat {path} -c %a:%U:%G").strip()
      assert permissions == expected, f"expected: {expected}, got {permissions}"

    def assert_logdir():
      assert_file_permissions("755:root:nginx", "/var/log/nginx")
      assert_file_permissions("644:root:nginx", "/var/log/nginx/performance.log")
      assert_file_permissions("644:root:nginx", "/var/log/nginx/error.log")
      assert_file_permissions("644:root:nginx", "/var/log/nginx/access.log")

    with subtest("proxy cache directory should be accessible only for nginx"):
      assert_file_permissions("700:nginx:nginx", "/var/cache/nginx/proxy")

    with subtest("log directory should have correct permissions"):
      assert_logdir()

    with subtest("dependencies between acme services and nginx-config-reload should be present"):
      after = server.succeed("systemctl show --property After --value nginx-config-reload.service")
      assert "acme-server.service" in after, f"acme.server.service missing: {after}"
      before = server.succeed("systemctl show --property Before --value nginx-config-reload.service")
      assert "acme-finished-server.target" in before, f"acme-finished-server.target missing: {before}"
      server.succeed("stat /etc/systemd/system/acme-server.service.wants/nginx-config-reload.service")

    with subtest("nginx should forward proxied host and server headers (primary name)"):
      server.execute("cat /etc/proxy.http | nc -l 8008 -N > /tmp/proxy.log &")
      server.succeed("curl http://server/proxy/")
      server.sleep(0.5)
      _, proxy_log = server.execute("cat /tmp/proxy.log")
      print(proxy_log)
      assert 'X-Forwarded-Host: server' in proxy_log, f"expected X-Forwarded-Host not found, got '{proxy_log}'"
      assert 'X-Forwarded-Server: server' in proxy_log, f"expected X-Forwarded-Server not found, got '{proxy_log}'"

    with subtest("nginx should forward proxied host and server headers (alias)"):
      server.execute("cat /etc/proxy.http | nc -l 8008 -N > /tmp/proxy.log &")
      server.succeed("curl http://other/proxy/")
      server.sleep(0.5)
      _, proxy_log = server.execute("cat /tmp/proxy.log")
      print(proxy_log)
      assert 'X-Forwarded-Host: other' in proxy_log, f"expected X-Forwarded-Host not found, got: '{proxy_log}'"
      assert 'X-Forwarded-Server: server' in proxy_log, f"expected X-Forwarded-Server not found, got: '{proxy_log}'"

    with subtest("nginx should respond with configured content"):
      server.succeed("curl server | grep -q 'initial content'")

    with subtest("running nginx should have the expected version"):
      server.succeed("curl server/404 | grep -q ${stableMajorVersion}")

    with subtest("nginx should use changed config after reload"):
      # Replace config symlink with a new config file.
      server.execute("sed 's#${rootInitial}#${rootChanged}#' /etc/nginx/nginx.conf > /etc/nginx/changed_nginx.conf")
      server.execute("mv /etc/nginx/changed_nginx.conf /etc/nginx/nginx.conf")
      server.systemctl("reload nginx")
      server.wait_until_succeeds("curl server | grep -q 'changed content'")

    with subtest("logs should have correct permissions after reload"):
      assert_logdir()

    with subtest("nginx should use changed binary after reload"):
      # Prepare change to mainline nginx. We are not interested in testing mainline itself here.
      # We only need it as a different version so we can test binary reloading.
      server.execute("ln -sfT ${pkgs.nginxMainline} /etc/nginx/running-package")
      # Mainline doesn't know about our custom remote_addr_anon variable, patch our config.
      server.execute("sed 's#remote_addr_anon#remote_addr#' /etc/nginx/nginx.conf > /etc/nginx/changed_nginx.conf")
      server.execute("mv /etc/nginx/changed_nginx.conf /etc/nginx/nginx.conf")
      # Go to mainline (this doesn't overwrite /etc/nginx/running-package).
      server.succeed("nginx-reload-master")
      server.wait_until_succeeds("curl server/404 | grep -q ${mainlineMajorVersion}")
      # Back to initial binary from nginx stable (this does overwrite /etc/nginx/running-package with the wanted package).
      server.systemctl("reload nginx")
      server.wait_until_succeeds("curl server/404 | grep -q ${stableMajorVersion}")

    with subtest("log directory should have correct permissions after binary reload"):
      assert_logdir()

    with subtest("logs should have correct permissions after logrotate"):
      server.succeed("logrotate -f $(logrotate-config-file)")
      assert_logdir()

    with subtest("reload should fix wrong log permissions and recreate missing files"):
      server.execute("chown nginx:nginx /var/log/nginx/performance.log")
      server.execute("chown nobody:nobody /var/log/nginx/access.log")
      server.execute("rm /var/log/nginx/error.log")
      server.succeed("systemctl reload nginx")
      assert_logdir()

    with subtest("restart should fix wrong log permissions and recreate missing files"):
      server.execute("chown nginx:nginx /var/log/nginx/performance.log")
      server.execute("chown nobody:nobody /var/log/nginx/access.log")
      server.execute("rm /var/log/nginx/error.log")
      server.succeed("systemctl restart nginx")
      assert_logdir()

    with subtest("nginx modsecurity rules apply"):
      out, err = server.execute("curl -v http://server/?testparam=test")
      print(out)
      print(err)

    with subtest("service user should be able to write to local config dir"):
      server.succeed('sudo -u nginx touch /etc/local/nginx/vhosts.json')

    with subtest("all sensu checks should be green"):
      server.succeed("${sensuCheck "nginx_config"}")
      server.succeed("${sensuCheck "nginx_worker_age"}")
      server.succeed("${sensuCheck "nginx_status"}")

    with subtest("killing the nginx process should trigger an automatic restart"):
      server.succeed("pkill -9 -F /run/nginx/nginx.pid");
      server.wait_until_succeeds("${sensuCheck "nginx_status"}")

    with subtest("status check should be red after shutting down nginx"):
      server.systemctl('stop nginx')
      server.fail("${sensuCheck "nginx_status"}")

    with subtest("dhparams file should contain something"):
      server.wait_for_unit("dhparams-init.service")
      server.succeed("test -s /var/lib/dhparams/nginx.pem")
  '';
})
