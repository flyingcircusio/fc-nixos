import ./make-test-python.nix ({ ... }:
{
  name = "lamp";
  nodes = {
    lamp =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.roles.lamp = {
          enable = true;

          vhosts = [ { port = 8000; docroot = "/srv/docroot"; } ];

          apache_conf = ''
            # XXX test-i-am-the-custom-apache-conf
          '';

          php_ini = ''
            # XXX test-i-a-m-the-custom-php-ini
          '';
        };
      };
  };

  testScript = { nodes, ... }:
    ''
    def assert_listen(machine, process_name, expected_sockets):
      result = machine.succeed(f"netstat -tlpn | grep {process_name} | awk '{{ print $4 }}'")
      actual = set(result.splitlines())
      assert expected_sockets == actual, f"expected sockets: {expected_sockets}, found: {actual}"

    lamp.wait_for_unit("httpd.service")
    lamp.wait_for_open_port(8000)

    lamp.wait_for_unit("tideways-daemon.service")
    lamp.wait_for_open_port(9135)

    lamp.succeed("journalctl -u tideways.daemon")

    with subtest("apache (httpd) opens expected ports"):
      assert_listen(lamp, "httpd", {"127.0.0.1:7999", "::1:7999", ":::8000"})

    with subtest("our changes for config files should be there"):
      lamp.succeed("grep 'custom-apache-conf' ${nodes.lamp.config.services.httpd.configFile}")
      lamp.succeed("grep 'custom-php-ini' ${nodes.lamp.config.systemd.services.httpd.environment.PHPRC}")

    with subtest("check if PHP support is working as expected"):
      lamp.succeed('mkdir -p /srv/docroot')
      lamp.succeed('echo "<? phpinfo(); ?>" > /srv/docroot/test.php')

      lamp.succeed("curl -f -v http://localhost:8000/test.php -o result")
      lamp.succeed("grep 'tideways.api_key' result")
      lamp.succeed("grep 'files user memcached redis rediscluster' result")
      lamp.succeed("grep module_redis result")
      lamp.succeed("grep module_imagick result")
      lamp.succeed("grep module_memcached result")
      lamp.succeed("grep -e 'short_open_tag.*On' result")
      lamp.succeed("grep -e 'output_buffering.*>1<' result")
      lamp.succeed("grep -e 'curl.cainfo.*/etc/ssl/certs/ca-certificates.crt' result")
      lamp.succeed("grep -e 'Path to sendmail.*sendmail -t -i' result")

      lamp.succeed("grep -e 'opcache.enable.*On' result")

      lamp.succeed("grep -e 'error_log.*syslog' result")
      lamp.succeed("grep -e 'display_errors.*Off' result")
      lamp.succeed("grep -e 'log_errors.*On' result")

      lamp.succeed("grep -e 'memory_limit.*1024m' result")
      lamp.succeed("grep -e 'max_execution_time.*800' result")
      lamp.succeed("grep -e 'session.auto_start.*Off' result")
    '';

})
