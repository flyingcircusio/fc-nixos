import ./make-test-python.nix ({ lib, pkgs, testlib, ... }:

let
  stableMajorVersion = "1.18";
  mainlineMajorVersion = "1.19";

  rootInitial = pkgs.runCommand "nginx-root-initial" {} ''
    mkdir $out
    echo initial content > $out/index.html
  '';

  rootChanged = pkgs.runCommand "nginx-root-changed" {} ''
    mkdir $out
    echo changed content > $out/index.html
  '';
in {
  name = "nginx";
  machine =
    { lib, pkgs, ... }:
    {
      imports = [ ../nixos ];
      networking.hosts."192.168.1.1" = [ "other" ];
      environment.etc."proxy.http".text = ''
        HTTP/1.1 200 OK
        Content-Type: text/html; charset=UTF-8
        Server: netcat!

        <!doctype html>
        <html><body><h1>A webpage served by netcat</h1></body></html>
      '';
      flyingcircus.services.nginx.enable = true;

      # Vhost for localhost is predefined by the nginx module and serves the
      # nginx status page which is expected by the sensu check.

      # Vhost for config reload check.
      services.nginx.virtualHosts.machine = {
        root = rootInitial;
        serverAliases = [ "other" ];
        locations."/proxy".proxyPass = "http://127.0.0.1:8008";
      };

      # Display the nginx version on the 404 page.
      services.nginx.serverTokens = true;
    };

  testScript = { nodes, ... }:
  let
    sensuCheck = testlib.sensuCheckCmd nodes.machine;
  in ''
    machine.wait_for_unit('nginx.service')
    machine.wait_for_open_port(80)

    with subtest("nginx should forward proxied host and server headers (primary name)"):
      machine.execute("cat /etc/proxy.http | nc -l 8008 -N > /tmp/proxy.log &")
      machine.succeed("curl http://machine/proxy/")
      _, proxy_log = machine.execute("cat /tmp/proxy.log")
      print(proxy_log)
      assert 'X-Forwarded-Host: machine' in proxy_log
      assert 'X-Forwarded-Server: machine' in proxy_log

    with subtest("nginx should forward proxied host and server headers (alias)"):
      machine.execute("cat /etc/proxy.http | nc -l 8008 -N > /tmp/proxy.log &")
      machine.succeed("curl http://other/proxy/")
      _, proxy_log = machine.execute("cat /tmp/proxy.log")
      print(proxy_log)
      assert 'X-Forwarded-Host: other' in proxy_log
      assert 'X-Forwarded-Server: machine' in proxy_log

    with subtest("nginx should respond with configured content"):
      machine.succeed("curl machine | grep -q 'initial content'")

    with subtest("running nginx should have the expected version"):
      machine.succeed("curl machine/404 | grep -q ${stableMajorVersion}")

    with subtest("nginx should use changed config after reload"):
      # Replace config symlink with a new config file.
      machine.execute("sed 's#${rootInitial}#${rootChanged}#' /run/nginx/config > /run/nginx/changed_config")
      machine.execute("mv /run/nginx/changed_config /run/nginx/config")
      # Trigger reload manually because the reload script would reset the symlink.
      machine.systemctl("kill -s HUP nginx")
      machine.wait_until_succeeds("curl machine | grep -q 'changed content'")
      # Back to initial configuration from Nix store.
      machine.systemctl("reload nginx")
      machine.wait_until_succeeds("curl machine | grep -q 'initial content'")

    with subtest("nginx should use changed binary after reload"):
      # Prepare change to mainline nginx. We are not interested in testing mainline itself here.
      # We only need it as a different version so we can test binary reloading.
      machine.execute("ln -sfT ${pkgs.nginxMainline} /run/nginx/package")
      # Mainline doesn't know about our custom remote_addr_anon variable, patch our config.
      machine.execute("sed 's#remote_addr_anon#remote_addr#' /run/nginx/config > /run/nginx/changed_config")
      machine.execute("mv /run/nginx/changed_config /run/nginx/config")
      # Go to mainline.
      machine.succeed("nginx-reload-master")
      machine.wait_until_succeeds("curl machine/404 | grep -q ${mainlineMajorVersion}")
      # Back to initial binary from nginx stable.
      machine.systemctl("reload nginx")
      machine.wait_until_succeeds("curl machine/404 | grep -q ${stableMajorVersion}")

    with subtest("service user should be able to write to local config dir"):
      machine.succeed('sudo -u nginx touch /etc/local/nginx/vhosts.json')

    with subtest("all sensu checks should be green"):
      machine.succeed("${sensuCheck "nginx_config"}")
      machine.succeed("${sensuCheck "nginx_worker_age"}")
      machine.succeed("${sensuCheck "nginx_status"}")

    with subtest("killing the nginx process should trigger an automatic restart"):
      machine.succeed("pkill -9 -F /run/nginx/nginx.pid");
      machine.wait_until_succeeds("${sensuCheck "nginx_status"}")

    with subtest("status check should be red after shutting down nginx"):
      machine.systemctl('stop nginx')
      machine.fail("${sensuCheck "nginx_status"}")
  '';
})
