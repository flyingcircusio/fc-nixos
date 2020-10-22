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
    ${server6Fe} = [ "server" ];
    ${server4Fe} = [ "server" ];
  };

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

      flyingcircus.services.nginx.enable = true;

      # Vhost for localhost is predefined by the nginx module and serves the
      # nginx status page which is expected by the sensu check.

      # Vhost for config reload check.
      services.nginx.virtualHosts.server = {
        root = rootInitial;
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

    with subtest("nginx should respond with configured content"):
      server.succeed("curl server | grep -q 'initial content'")

    with subtest("running nginx should have the expected version"):
      server.succeed("curl server/404 | grep -q ${stableMajorVersion}")

    with subtest("nginx should use changed config after reload"):
      # Replace config symlink with a new config file.
      server.execute("sed 's#${rootInitial}#${rootChanged}#' /run/nginx/config > /run/nginx/changed_config")
      server.execute("mv /run/nginx/changed_config /run/nginx/config")
      # Trigger reload manually because the reload script would reset the symlink.
      server.systemctl("kill -s HUP nginx")
      server.wait_until_succeeds("curl server | grep -q 'changed content'")
      # Back to initial configuration from Nix store.
      server.systemctl("reload nginx")
      server.wait_until_succeeds("curl server | grep -q 'initial content'")

    with subtest("nginx should use changed binary after reload"):
      # Prepare change to mainline nginx. We are not interested in testing mainline itself here.
      # We only need it as a different version so we can test binary reloading.
      server.execute("ln -sfT ${pkgs.nginxMainline} /run/nginx/package")
      # Mainline doesn't know about our custom remote_addr_anon variable, patch our config.
      server.execute("sed 's#remote_addr_anon#remote_addr#' /run/nginx/config > /run/nginx/changed_config")
      server.execute("mv /run/nginx/changed_config /run/nginx/config")
      # Go to mainline.
      server.succeed("nginx-reload-master")
      server.wait_until_succeeds("curl server/404 | grep -q ${mainlineMajorVersion}")
      # Back to initial binary from nginx stable.
      server.systemctl("reload nginx")
      server.wait_until_succeeds("curl server/404 | grep -q ${stableMajorVersion}")

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
  '';
})
