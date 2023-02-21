import ../make-test-python.nix ({ version ? "" , tideways ? "", lib, ... }:
{
  name = "lamp";
  extraPythonPackages = p: with p; [ packaging ];
  nodes = {
    lamp =
      { pkgs, config, ... }:
      {
        imports = [ ../../nixos ../../nixos/roles ];

        virtualisation.memorySize = 3000;

        flyingcircus.enc.parameters = {
          resource_group = "test";
          interfaces.srv = {
            mac = "52:54:00:12:34:56";
            bridged = false;
            networks = {
              "192.168.101.0/24" = [ "192.168.101.1" ];
              "2001:db8:f030:1c3::/64" = [ "2001:db8:f030:1c3::3" ];
            };
            gateways = {};
          };
        };

        flyingcircus.roles.lamp = {
          enable = true;

          vhosts = [ { port = 8000; docroot = "/srv/docroot"; }
                     { port = 8001; docroot = "/srv/docroot2"; }
                   ];

          php = pkgs.lib.mkIf (version != "") pkgs.${version};

          apache_conf = ''
            # XXX test-i-am-the-custom-apache-conf
          '';

          php_ini = ''
            # XXX test-i-a-m-the-custom-php-ini
          '';

          tideways_api_key = tideways;

        };

        virtualisation.qemu.options = [ "-smp 2" ];
      };
  };

  testScript = { nodes, ... }:
    ''
    from packaging.version import Version
    import time
    def assert_listen(machine, process_name, expected_sockets):
      result = machine.succeed(f"netstat -tlpn | grep {process_name} | awk '{{ print $4 }}'")
      actual = set(result.splitlines())
      assert expected_sockets == actual, f"expected sockets: {expected_sockets}, found: {actual}"

    lamp.wait_for_unit("httpd.service")
    lamp.wait_for_open_port(8000)

    php_version_str = lamp.succeed('php --version').splitlines()[0]
    php_version_str = php_version_str.split()[1]
    php_version = Version(php_version_str)
    print("Detected PHP version:", php_version)

    tideways_api_key = "${tideways}"

    if tideways_api_key:
      lamp.wait_for_unit("tideways-daemon.service")
      lamp.wait_for_open_port(9135)
      print(lamp.succeed("echo '{\"type\": \"phpinfo\"}' | nc 127.0.0.1 9135"))

    with subtest("apache (httpd) opens expected ports"):
      assert_listen(lamp, "httpd", {"127.0.0.1:7999", "::1:7999", ":::8000", ":::8001"})

    print(lamp.execute("cat /etc/httpd/httpd.conf")[1])
    print(lamp.execute("cat $PHPRC")[1])

    lamp.succeed('mkdir -p /srv/docroot')
    lamp.succeed('echo "<? phpinfo(); ?>" > /srv/docroot/test.php')

    lamp.succeed('mkdir -p /srv/docroot2')
    lamp.succeed('echo "<? phpinfo(); ?>" > /srv/docroot2/test.php')

    with subtest("check that the FPM pools are not being confused"):
      print("Warming up Apache")
      for x in range(20):
        print("warmup round", x)
        print("warming up 8001")
        _, output = lamp.execute("curl -v http://localhost:8001/test.php -o /dev/null 2>&1")
        print(output)
        #assert "200 OK" in output

        print("warming up 8000")
        _, output = lamp.execute("curl -v http://localhost:8000/test.php -o /dev/null 2>&1")
        print(output)
        #assert "200 OK" in output

      print(lamp.execute("journalctl --since -10s"))

      print("Stopping 8001")
      lamp.succeed("systemctl stop phpfpm-lamp-8001.service")

      print("Expecting port 8001 to be down")
      for x in range(50):
        _, output = lamp.execute("curl -v http://localhost:8000/test.php -o /dev/null 2>&1")
        assert "200 OK" in output
        code, output = lamp.execute("curl -v http://localhost:8001/test.php -o /dev/null 2>&1")
        if "503 Service Unavailable" not in output:
          print(output)
          raise AssertionError("Unexpected non-503 result")

    with subtest("apache reload works"):
      # PL-130372 broke repeatedly after 7-11 tries
      for x in range(10):
        print("="*80)
        print(f"Reload try {x}")
        lamp.succeed("systemctl reload httpd")
        time.sleep(0.1)
        code, output = lamp.execute("grep 'TLS block' /var/log/httpd/error.log")
        if not code:
            print(lamp.succeed("tail -n 5000 /var/log/httpd/error.log"))
            assert False, f"Failure after {x} reloads"

    with subtest("check if composer CLI is installed"):
      lamp.succeed("su nobody -s /bin/sh -c 'composer --help'")

    with subtest("check if PHP support is working as expected in CLI"):
      lamp.succeed("php /srv/docroot/test.php > result")
      print(lamp.succeed('cat result'))
      print(lamp.succeed('set'))

      lamp.succeed("egrep 'Registered save handlers.*files' result")
      lamp.succeed("egrep 'Registered save handlers.*user' result")
      if php_version.major > 5:
        lamp.succeed("egrep 'Registered save handlers.*redis' result")
        lamp.succeed("egrep 'Registered save handlers.*memcached' result")

      lamp.succeed("egrep 'Redis Support => enabled' result")
      lamp.succeed("egrep 'imagick module => enabled' result")
      lamp.succeed("egrep 'memcached support => enabled' result")
      lamp.succeed("egrep 'short_open_tag.*On' result")
      lamp.succeed("egrep 'output_buffering => 0 => 0' result")

      if php_version >= Version("7.3"):
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

      # PL-129824 PHP (5.6) locales
      lamp.succeed("php -r 'var_dump(setlocale(LC_TIME, \"de_DE.UTF8\"));' | grep de_DE")

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

      if php_version >= Version("7.3"):
        lamp.succeed("egrep 'curl.cainfo.*/etc/ssl/certs/ca-certificates.crt' result")

      if tideways_api_key:
        print(lamp.succeed("egrep 'tideways' result"))
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
