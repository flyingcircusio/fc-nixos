import ./make-test.nix ({ ... }:
{
  name = "nginx";
  machine =
    { ... }:
    {
      imports = [ ../nixos ];
      flyingcircus.services.nginx.enable = true;
    };
  testScript = ''
    $machine->waitForUnit('nginx.service');
    $machine->succeed(<<_EOT_);
      curl -v http://localhost/nginx_status | \
      grep "server accepts handled requests"
    _EOT_

    # service user should be able to write to local config dir
    $machine->succeed('sudo -u nginx touch /etc/local/nginx/vhosts.json');
  '';
})
