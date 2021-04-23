import ./make-test-python.nix ({ version ? "" , tideways ? "", ... }:
{
  name = "lamp";
  nodes = {
    lamp =
      { pkgs, config, ... }:
      {
        imports = [ ../nixos ../nixos/roles ];

        flyingcircus.roles.lamp = {
          enable = true;

          vhosts = [ { port = 8000; docroot = "/srv/docroot"; } ];

          php = pkgs.lib.mkIf (version != "") pkgs.${version};

          apache_conf = ''
            # XXX test-i-am-the-custom-apache-conf
          '';

          php_ini = ''
            # XXX test-i-a-m-the-custom-php-ini
          '';

          tideways_api_key = tideways;

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

    php_version = lamp.succeed('php --version').splitlines()[0]
    php_version = php_version.split()[1]
    php_version = int(php_version.split('.')[0])
    print("Detected PHP major version: ", php_version)

    tideways_api_key = "${tideways}"

    if tideways_api_key:
      lamp.wait_for_unit("tideways-daemon.service")
      lamp.wait_for_open_port(9135)

    with subtest("apache (httpd) opens expected ports"):
      assert_listen(lamp, "httpd", {"127.0.0.1:7999", "::1:7999", ":::8000"})

    with subtest("our changes for config files should be there"):
      lamp.succeed("grep 'custom-apache-conf' ${nodes.lamp.config.services.httpd.configFile}")
      lamp.succeed("grep 'custom-php-ini' ${nodes.lamp.config.systemd.services.httpd.environment.PHPRC}")

    lamp.succeed('mkdir -p /srv/docroot')
    lamp.succeed('echo "<? phpinfo(); ?>" > /srv/docroot/test.php')

    with subtest("check if PHP support is working as expected in CLI"):
      lamp.succeed("php /srv/docroot/test.php > result")
      print(lamp.succeed('cat result'))
      print(lamp.succeed('set'))

      lamp.succeed("egrep 'Registered save handlers.*files' result")
      lamp.succeed("egrep 'Registered save handlers.*user' result")
      if php_version > 5:
        lamp.succeed("egrep 'Registered save handlers.*redis' result")
        lamp.succeed("egrep 'Registered save handlers.*memcached' result")

      lamp.succeed("egrep 'Redis Support => enabled' result")
      lamp.succeed("egrep 'imagick module => enabled' result")
      lamp.succeed("egrep 'memcached support => enabled' result")
      lamp.succeed("egrep 'short_open_tag.*On' result")
      lamp.succeed("egrep 'output_buffering => 0 => 0' result")

      if php_version > 5:
        lamp.succeed("egrep 'curl.cainfo.*/etc/ssl/certs/ca-certificates.crt' result")

      if tideways_api_key:
        lamp.succeed("egrep 'tideways' result")
        lamp.succeed("grep 'Can connect to tideways-daemon?.*Yes' result")

      lamp.succeed("egrep 'Path to sendmail.*sendmail -t -i' result")
      lamp.succeed("egrep 'opcache.enable => On => On' result")
      lamp.succeed("egrep 'opcache.enable_cli => Off => Off' result")

      lamp.succeed("egrep 'error_log.*syslog' result")
      lamp.succeed("egrep 'display_errors.*Off' result")
      lamp.succeed("egrep 'log_errors.*On' result")

      lamp.succeed("egrep 'memory_limit.*1024m' result")
      lamp.succeed("egrep 'max_execution_time => 0 => 0' result")
      lamp.succeed("egrep 'session.auto_start.*Off' result")
      lamp.succeed("egrep 'BCMath support.*enabled' result")

    with subtest("check if PHP support is working as expected in apache"):
      lamp.succeed("w3m -cols 400 -dump http://localhost:8000/test.php > result")
      print(lamp.succeed('cat result'))

      lamp.succeed("egrep 'Registered save handlers.*files' result")
      lamp.succeed("egrep 'Registered save handlers.*user' result")
      lamp.succeed("egrep 'Registered save handlers.*redis' result")
      lamp.succeed("egrep 'Registered save handlers.*memcached' result")

      lamp.succeed("egrep 'Redis Support +enabled' result")
      lamp.succeed("egrep 'imagick module +enabled' result")
      lamp.succeed("egrep 'memcached support +enabled' result")
      lamp.succeed("egrep 'short_open_tag.*On' result")
      lamp.succeed("egrep 'output_buffering +1 +1' result")
      lamp.succeed("egrep 'BCMath support.*enabled' result")

      if php_version > 5:
        lamp.succeed("egrep 'curl.cainfo.*/etc/ssl/certs/ca-certificates.crt' result")

      if tideways_api_key:
        lamp.succeed("egrep 'tideways' result")
        lamp.succeed("grep 'Can connect to tideways-daemon?.*Yes' result")

      lamp.succeed("egrep 'Path to sendmail.*sendmail -t -i' result")
      lamp.succeed("egrep 'opcache.enable.*On' result")

      lamp.succeed("egrep 'error_log.*syslog' result")
      lamp.succeed("egrep 'display_errors.*Off' result")
      lamp.succeed("egrep 'log_errors.*On' result")

      lamp.succeed("egrep 'memory_limit.*1024m' result")
      lamp.succeed("egrep 'max_execution_time.*800' result")
      lamp.succeed("egrep 'session.auto_start.*Off' result")

    '';

})
