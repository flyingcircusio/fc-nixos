import ./make-test.nix ({ ... }:
{
  name = "lamp";
  nodes = {
    lamp =
      { ... }:
      {
        imports = [ ../nixos ../nixos/roles ];
        flyingcircus.roles.lamp.enable = true;

        # On real machines this is fed via /etc/local/lamp/docroot and 
        flyingcircus.roles.lamp.simple_docroot = true;
        # ... /etc/local/lamp/*.vhost.json
        flyingcircus.roles.lamp.vhosts = [ { port = 8100; docroot = "/srv/docroot2"; } ];
      };
  };

  testScript = ''
    $lamp->waitForUnit("httpd.service");
    $lamp->waitForOpenPort(8000);

    $lamp->waitForUnit("tideways-daemon.service");
    $lamp->waitForOpenPort(9135);

    $lamp->succeed('journalctl -u tideways.daemon');

    # The simple docroot
    $lamp->succeed('mkdir -p /srv/docroot');
    $lamp->succeed('ln -s /srv/docroot /etc/local/lamp/docroot');
    $lamp->succeed('echo "<? phpinfo(); ?>" > /srv/docroot/test.php');

    $lamp->succeed("curl -f -v http://localhost:8000/test.php -o result");
    $lamp->succeed("grep 'tideways.api_key' result");
    $lamp->succeed("grep 'files user memcached redis rediscluster' result");
    $lamp->succeed("grep module_redis result");
    $lamp->succeed("grep module_imagick result");
    $lamp->succeed("grep module_memcached result");
    $lamp->succeed("grep -e 'short_open_tag.*On' result");
    $lamp->succeed("grep -e 'output_buffering.*>1<' result");
    $lamp->succeed("grep -e 'curl.cainfo.*/etc/ssl/certs/ca-certificates.crt' result");
    $lamp->succeed("grep -e 'Path to sendmail.*sendmail -t -i' result");

    $lamp->succeed("grep -e 'opcache.enable.*On' result");

    $lamp->succeed("grep -e 'error_log.*syslog' result");
    $lamp->succeed("grep -e 'display_errors.*Off' result");
    $lamp->succeed("grep -e 'log_errors.*On' result");

    $lamp->succeed("grep -e 'memory_limit.*1024m' result");
    $lamp->succeed("grep -e 'max_execution_time.*800' result");
    $lamp->succeed("grep -e 'session.auto_start.*Off' result");

    # The .vhost.json based docroot
    $lamp->succeed('mkdir -p /srv/docroot2');
    $lamp->succeed('echo "{\"port\": 8100, \"docroot\": \"/srv/docroot2\"}" > /etc/local/lamp/test2.vhost.json');
    $lamp->succeed('echo "<? phpinfo(); ?>" > /srv/docroot2/test2.php');
    $lamp->succeed("curl -f -v http://localhost:8100/test2.php -o result2");
    $lamp->succeed("grep 'tideways.api_key' result2");
  '';

})
