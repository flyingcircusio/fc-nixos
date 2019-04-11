import ./make-test.nix ({ ... }:
{
  name = "nginx";
  machine =
    { ... }:
    {
      imports = [ ../nixos ];
      flyingcircus.services.nginx.enable = true;
      environment.etc."local/nginx/mysite.conf".text = ''
        # simple vhost serving its own config
        server {
          listen *:80;
          server_name machine;
          root /etc/local/nginx;
        }
      '';
    };
  testScript = ''
    $machine->waitForUnit('nginx.service');
    $machine->succeed(<<_EOT_);
      curl -v http://machine/mysite.conf | grep "serving its own config"
    _EOT_
    $machine->succeed(<<_EOT_);
      curl -v http://localhost/nginx_status | \
      grep "server accepts handled requests"
    _EOT_
    $machine->succeed('grep mysite.conf /var/log/nginx/access.log');
  '';
})
